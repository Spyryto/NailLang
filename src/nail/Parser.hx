package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;
import nail.SumLowering;

/** Whitespace-delimited lexer + small precedence parser, with desugaring to Expr. */
class Parser {
  final tokens:Array<String>;
  /** Experimental opt-in contextual DSL interfaces. This deliberately
      does not change the normal 0.54 parser or language version. The
      caller supplies visible field names (from a checked interface). */
  final contextFields:Null<haxe.ds.StringMap<Array<String>>>;
  /** Explicitly opted-in, experimental contextual + open-row inference.
      Normal versioned 0.54 programs retain their current type semantics. */
  public final experimentalContexts:Bool;
  var nextContext:Int = 0;
  /** Original token coordinates, parallel to tokens. */
  public final tokenPositions:Array<nail.SourcePositions.SourceToken>;
  /** Optional original-source spans for the parser's core nodes. */
  public final provenance:SourceProvenance;
  var at:Int = 0;

  static final namePattern = ~/^[A-Za-z_][A-Za-z_0-9]*$/;
  static final recordTypePattern = ~/^[A-Z][A-Za-z_0-9]*$/;
  static final typeParamPattern = ~/^[a-z][a-z0-9_]*$/;
  static final numberPattern = ~/^-?(?:\d+(?:\.\d+)?|\.\d+)$/;

  final exactMode:Bool;
  public final modernMode:Bool;
  public final languageVersion:Null<String>;
  public final declaredDivRows:Array<{left:String, right:String, result:String}>;
  public final declaredOperatorRows:haxe.ds.StringMap<Array<{left:String,right:String,result:String}>>;
  /** Opt-in type relation declarations; erased before bytecode generation. */
  public final declaredRelations:haxe.ds.StringMap<String>;
  /** Generalized v0.49 relation signatures (type names, result last). */
  public final generalRows:haxe.ds.StringMap<Array<Array<String>>>;


  public function new(source:String,
      ?contextFields:haxe.ds.StringMap<Array<String>>) {
    this.contextFields=contextFields;
    this.experimentalContexts=contextFields!=null;
    languageVersion = numeric.LanguageVersion.declared(source);
    modernMode = languageVersion != null;
    exactMode = numeric.NumericDialect.isExact(source);
    declaredDivRows = [];
    declaredOperatorRows = new haxe.ds.StringMap();
    if (modernMode && exactMode) throw 'Source cannot combine numeric dialects';
    declaredRelations = new haxe.ds.StringMap<String>();
    generalRows = new haxe.ds.StringMap();
    tokenPositions = SourcePositions.scan(source);
    provenance = new SourceProvenance(tokenPositions);
    tokens = [for (token in tokenPositions) token.text];
    if (modernMode) at = 3; // explicit versioned Nail source header
  }

  // String boundaries are separate whitespace-delimited tokens: " hello world ".
  // Contents are joined with one space and decoded as JSON string escapes.
  // Comments are ignored outside quoted text only.
  static function isName(s:Null<String>):Bool {
    if (s == null || !namePattern.match(s)) return false;
    return switch (s) {
      case 'nail' | 'import' | 'from' | 'export' | 'macro' | 'quote' | 'unquote' | 'expand' | 'def' | 'type' | 'if' | 'then' | 'else' | 'fun' | 'function' | 'true' | 'false' | 'let' | 'in' | 'match' | 'with': false;
      case _: true;
    };
  }

  static function isNumber(s:Null<String>):Bool return s != null && numberPattern.match(s);

  static function beginsAtom(s:Null<String>):Bool {
    return switch (s) {
      case 'quote' | 'unquote' | 'expand' | '(' | '[' | '[]' | '{' | 'fun' | 'function' | 'if' | 'let' | 'match' | 'true' | 'false': true;
      case _: (s != null && StringTools.startsWith(s, '\u0001')) || isName(s) || isNumber(s);
    };
  }

  static function exactBuiltinName(name:String):String return switch (name) {
    case 'textLength': 'textLengthExact';
    case 'textAt': 'textAtExact';
    case 'vectorLength': 'vectorLengthExact';
    case 'vectorGet': 'vectorGetExact';
    case 'vectorSet': 'vectorSetExact';
    case _: name;
  };

  static function modernBuiltinName(name:String):String return switch (name) {
    case 'textLength' | 'textAt' | 'vectorLength' | 'vectorGet' | 'vectorSet': name + 'Int';
    case _: name;
  };

  static function precedence(s:Null<String>):Int {
    return switch (s) {
      case '==' | '!=' | '<' | '<=' | '>' | '>=': 30;
      case '+' | '-': 40;
      case '*' | '/': 50;
      case _: -1;
    };
  }

  inline function peek():Null<String> return at < tokens.length ? tokens[at] : null;
  inline function take():Null<String> return at < tokens.length ? tokens[at++] : null;

  function expect(token:String):Void {
    if (take() != token) throw 'Expected ' + token + ' at token ' + at;
  }

  function lambdas(params:Array<String>, body:Expr, ?starts:Array<Int>):Expr {
    var result = body;
    var i = params.length;
    while (i > 0) {
      i--;
      result = Lambda(params[i], result);
      if (starts != null) result = provenance.expression(result, starts[i], at);
    }
    return result;
  }

  /** Internal names cannot be written in source. Fixed names are safe here:
      each lowered list match introduces its own lexical lambda scope. This
      matches the pure Nail-written lowering and makes bytecode reproducible. */
  function hidden(label:String):String return '#nail_' + label + '_0';

  /** Surface let: ( fun name -> body ) value. A non-recursive, eager binding. */
  function parseLet():Expr {
    var bindingToken = at;
    var name = take();
    if (!isName(name) || name == '_') throw 'Invalid let binding name';
    expect('=');
    var value = expression();
    expect('in');
    var body = expression();
    var binder = provenance.expression(Lambda(name, body), bindingToken, at);
    return Apply(binder, value);
  }

  /** Exactly two exhaustive list patterns, [] and head :: tail, in either order.
      Core only sees if/lam/apply; the input is evaluated exactly once. */
  function parseMatch():Expr {
    var scrutinee = expression();
    expect('with');
    return parseMatchBranches(scrutinee);
  }

  /** Share exhaustive branches between ordinary match and F# function
      patterns, keeping the same five expression constructors. */
  function parseMatchBranches(scrutinee:Expr):Expr {
    if (peek() != '|') throw 'Expected | in match';
    var first:Null<String> = at + 1 < tokens.length ? tokens[at + 1] : null;
    var next:Null<String> = at + 2 < tokens.length ? tokens[at + 2] : null;
    if (first != null && recordTypePattern.match(first) && next != '::')
      return parseSumMatch(scrutinee);
    var emptyBranch:Null<Expr> = null;
    var pairBranch:Null<Expr> = null;
    var headName:Null<String> = null;
    var tailName:Null<String> = null;
    for (_ in 0...2) {
      expect('|');
      var first = take();
      if (first == '[]' || first == '[') {
        if (first == '[') expect(']');
        if (emptyBranch != null) throw 'Duplicate empty-list pattern';
        expect('->');
        emptyBranch = expression();
      } else {
        if (!isName(first)) throw 'Expected list pattern [] or head :: tail';
        expect('::');
        var second = take();
        if (!isName(second)) throw 'Expected list tail binding';
        if (first == second && first != '_') throw 'Duplicate list pattern binding';
        if (pairBranch != null) throw 'Duplicate cons-list pattern';
        headName = first == '_' ? hidden('wild_head') : first;
        tailName = second == '_' ? hidden('wild_tail') : second;
        expect('->');
        pairBranch = expression();
      }
    }
    if (emptyBranch == null || pairBranch == null || headName == null || tailName == null)
      throw 'Match requires [] and head :: tail patterns';
    var listName = hidden('list');
    var list:Expr = Var(listName);
    var call = (name:String, arg:Expr) -> Apply(Var(name), arg);
    var pair = Apply(Apply(Lambda(headName, Lambda(tailName, pairBranch)),
      call('#head', list)), call('#tail', list));
    return Apply(Lambda(listName, If(call('#isEmpty', list), emptyBranch, pair)), scrutinee);
  }

  function parseFunctionMatch():Expr {
    var name = hidden('function_subject');
    return Lambda(name, parseMatchBranches(Var(name)));
  }

  function parseSumMatch(scrutinee:Expr):Expr {
    var branches:Array<{name:String, params:Array<String>, body:Expr}> = [];
    while (peek() == '|') {
      take();
      var ctor = take();
      if (!isName(ctor) || !recordTypePattern.match(ctor)) throw 'Expected algebraic constructor';
      var params:Array<String> = [];
      while (peek() != '->') {
        var param = take();
        if (param == null || !isName(param)) throw 'Invalid variant binding';
        if (params.indexOf(param) >= 0 && param != '_') throw 'Duplicate variant binding';
        params.push(param);
        if (params.length > 10) throw 'Too many variant bindings';
      }
      expect('->');
      var body = expression();
      for (branch in branches) if (branch.name == ctor) throw 'Duplicate variant branch';
      branches.push({name:ctor, params:params, body:body});
    }
    return SumLowering.lowerMatch(scrutinee, branches);
  }

  function parseSumType(name:String):Form {
    var params:Array<String> = [];
    while (peek() != '=') {
      var p = take();
      if (!isName(p) || !typeParamPattern.match(p) || params.indexOf(p) >= 0)
        throw 'Invalid algebraic type parameter';
      params.push(p);
      if (params.length > 16) throw 'Too many type parameters';
    }
    expect('=');
    var ctors:Array<nail.Ast.SumConstructor> = [];
    var first = true;
    do {
      if (!first) expect('|');
      first = false;
      var ctor = take();
      if (!isName(ctor) || !recordTypePattern.match(ctor)) throw 'Expected algebraic constructor';
      var payload:Array<String> = [];
      while (peek() != '|' && peek() != ';') {
        var ty = take();
        if (!isName(ty)) throw 'Expected algebraic field type';
        payload.push(exactMode && ty == 'Number' ? 'Exact' : ty);
        if (payload.length > 10) throw 'Too many constructor fields';
      }
      for (previous in ctors) if (previous.name == ctor) throw 'Duplicate constructor';
      ctors.push({name:ctor, fieldTypes:payload});
      if (ctors.length > 32) throw 'Too many constructors';
    } while (peek() == '|');
    expect(';');
    if (ctors.length == 0) throw 'Algebraic type needs constructors';
    return SumType(name, params, ctors);
  }

  /** Surface named-record construction produces only existing core calls.
      Source-order fields stay in source-order #cons lists, so expressions
      are evaluated exactly once and from left to right. */
  static function namedList(values:Array<Expr>):Expr {
    var result:Expr = Literal(Nil);
    var i = values.length;
    while (i > 0) {
      i--;
      result = Apply(Apply(Var('#cons'), values[i]), result);
    }
    return result;
  }

  function parseNamedRecord(owner:String, opened:Bool = false):Expr {
    if (!opened) expect('{');
    var names:Array<Expr> = [];
    var values:Array<Expr> = [];
    var seen = new haxe.ds.StringMap<Bool>();
    if (peek() == '}') throw 'Named record requires at least one field';
    while (true) {
      var name = take();
      if (!isName(name) || name == '_') throw 'Expected named record field';
      if (seen.exists(name)) throw 'Duplicate named record field ' + name;
      seen.set(name, true);
      expect('=');
      names.push(Literal(Text(name)));
      values.push(expression());
      if (values.length > 128) throw 'Too many named record fields';
      if (peek() == '}') { take(); break; }
      expect(',');
      if (peek() == '}') throw 'Trailing comma in named record';
    }
    return Apply(Apply(Apply(Var('#recordMake'), Literal(Text(owner))),
      namedList(names)), namedList(values));
  }

  /** A context block and a record literal have disjoint openings:
      Name { field = expr ... } is an existing named-record constructor;
      Name { expression } opens a context if the experimental caller
      supplied a checked interface for Name.
      No new AST constructor or VM opcode: lower to nested lexical let
      bindings with a single receiver evaluation. */
  function parseContext(name:String):Expr {
    expect('{');
    var members=contextFields.get(name);
    if (members==null)
      throw 'Context probe: missing checked interface for '+name;
    if (members.length==0 || members.length>128)
      throw 'Context probe: invalid field count for '+name;
    var seen=new haxe.ds.StringMap<Bool>();
    for (member in members) {
      if (!isName(member) || member=='_' || seen.exists(member))
        throw 'Context probe: invalid or duplicate field '+member;
      seen.set(member,true);
    }
    var inner=expression();
    expect('}');
    // The internal name cannot be written by Nail source code.
    var receiver='#nail_context_'+(nextContext++);
    var i=members.length;
    while(i>0) {
      i--;
      var member=members[i];
      var projection:Expr=Apply(Apply(Var('#recordGet'),
        Var(receiver)),Literal(Text(member)));
      inner=Apply(Lambda(member,inner),projection);
    }
    return Apply(Lambda(receiver,inner),Var(name));
  }

  function atom():Expr {
    var first = at;
    return provenance.expression(atomUntracked(), first, at);
  }

  function atomUntracked():Expr {
    var token = take();
    if (token == null) throw 'Unexpected end of input';
    if (StringTools.startsWith(token, '\u0001')) return Literal(Text(token.substr(1)));
    if (token == 'quote' || token == 'unquote' || token == 'expand') return Var('#macro_' + token);
    if (token == '[]') return Literal(Nil);
    if (token == '{') return parseNamedRecord('#struct', true);
    if (token == '(') {
      // Collapse leading groups, then resume each group's Pratt suffix
      // after closing its inner parentheses.
      var depth = 1;
      while (peek() == '(') { take(); depth++; }
      var inner = expression();
      expect(')');
      while (--depth > 0) {
        inner = expressionSuffix(inner, 0);
        expect(')');
      }
      return inner;
    }
    if (token == '[') {
      var elements:Array<Expr> = [];
      if (peek() != ']') {
        while (true) {
          elements.push(expression());
          if (peek() != ',') break;
          take();
        }
      }
      expect(']');
      var result:Expr = Literal(Nil);
      var i = elements.length;
      while (i > 0) {
        i--;
        result = Apply(Apply(Var('#cons'), elements[i]), result);
      }
      return result;
    }
    if (token == 'let') return parseLet();
    if (token == 'match') return parseMatch();
    if (token == 'function') return parseFunctionMatch();
    if (token == 'if') {
      var condition = expression(); expect('then');
      var yes = expression(); expect('else');
      return If(condition, yes, expression());
    }
    if (token == 'fun') {
      var params:Array<String> = [];
      var positions:Array<Int> = [];
      while (peek() != '->') {
        var atParameter = at;
        var p = take();
        if (!isName(p) || params.indexOf(p) >= 0) throw 'Invalid or duplicate function parameter';
        params.push(p);
        positions.push(atParameter);
      }
      if (params.length == 0) throw 'Function needs at least one parameter';
      expect('->');
      return lambdas(params, expression(), positions);
    }
    if (isNumber(token)) {
      if (modernMode) return token.indexOf('.') >= 0
        ? Literal(Number(Std.parseFloat(token)))
        : Literal(IntNumber(numeric.FastNumber.exact(token)));
      if (exactMode) return Literal(ExactNumber(numeric.FastNumber.exact(
        StringTools.startsWith(token, '.') ? '0' + token :
        StringTools.startsWith(token, '-.') ? '-0' + token.substr(1) : token)));
      var number = Std.parseFloat(token);
      if (!Math.isFinite(number)) throw 'Number out of range: ' + token;
      return Literal(Number(number));
    }
    if (token == 'true' || token == 'false') return Literal(Boolean(token == 'true'));
    if (isName(token)) {
      if (peek() == '{') {
        // Syntactic lookahead only; never consult the type checker.
        // Uppercase Person { field = value } is a nominal constructor.
        // Lowercase render { field = value } remains *ordinary function
        // application* to an anonymous structural record, even when the
        // receiver has a contextual interface.
        var namedField=at+2<tokens.length && isName(tokens[at+1])
          && tokens[at+2]=='=';
        if (namedField) {
          if (recordTypePattern.match(token))
            return parseNamedRecord(token);
        } else {
          if (contextFields!=null && contextFields.exists(token))
            return parseContext(token);
          if (recordTypePattern.match(token))
            return parseNamedRecord(token);
        }
      }
      return Var(modernMode ? modernBuiltinName(token) : exactMode ? exactBuiltinName(token) : token);
    }
    throw 'Unexpected token ' + token + ' at token ' + at;
  }

  function expression(minimum:Int = 0):Expr {
    var first = at;
    return provenance.expression(expressionSuffix(atom(), minimum), first, at);
  }

  function expressionSuffix(left:Expr, minimum:Int):Expr {
    var first = provenance.startToken(left);
    while (peek() != null) {
      // Projection is explicit; binding power 80 (higher than application).
      if (peek() == '.' && minimum <= 80) {
        take();
        var field = take();
        if (!isName(field) || field == '_') throw 'Expected record field after .';
        left = Apply(Apply(Var('#recordGet'), left), Literal(Text(field)));
        if (first >= 0) left = provenance.expression(left, first, at);
        continue;
      }
      if (beginsAtom(peek()) && minimum <= 70) {
        left = Apply(left, expression(71));
        if (first >= 0) left = provenance.expression(left, first, at);
        continue;
      }
      var prec = precedence(peek());
      if (prec < minimum) break;
      var op = take();
      if (modernMode && op != '==' && op != '!=') op = '#modern' + op;
      else if (exactMode && op != '==' && op != '!=') op = '#exact' + op;
      left = Apply(Apply(Var(op), left), expression(prec + 1));
      if (first >= 0) left = provenance.expression(left, first, at);
    }
    return left;
  }

  /** Only simple named fields and previously declared record types in v0.17. */
  function parseRecordType(typeName:String):Form {
    if (!isName(typeName) || !recordTypePattern.match(typeName))
      throw 'Expected uppercase record type name';
    var params:Array<String> = [];
    while (peek() != '{') {
      var p = take();
      if (!isName(p) || !typeParamPattern.match(p) || params.indexOf(p) >= 0)
        throw 'Invalid or duplicate record type parameter';
      params.push(p);
      if (params.length > 16) throw 'Too many record type parameters';
    }
    expect('{');
    var fields:Array<nail.Ast.RecordField> = [];
    while (peek() != '}') {
      var fieldName = take();
      if (!isName(fieldName) || fieldName == '_') throw 'Expected record field name';
      var fieldType = take();
      if (!isName(fieldType)) throw 'Expected record field type';
      for (item in fields) if (item.name == fieldName) throw 'Duplicate record field ' + fieldName;
      fields.push({name:fieldName, typeName:exactMode && fieldType == 'Number' ? 'Exact' : fieldType});
      if (fields.length > 128) throw 'Too many record fields';
    }
    expect('}');
    expect(';');
    if (fields.length == 0) throw 'Record requires at least one field';
    return RecordType(typeName, params, fields);
  }

  public function parse(?modules:String->Null<String>):Array<Form> {
    var forms = parseRaw();
    var expanded = modules == null ? MacroExpander.forms(forms)
      : SyntaxBridge.forms(MacroExpander.syntax(SyntaxEncoder.program(forms), name -> {
        var source = modules(name);
        if (source == null) return null;
        MacroModuleDialect.requireCompatible(languageVersion, exactMode, source, name);
        return SyntaxEncoder.program(new Parser(source).parseRaw());
      }));
    // Macro declarations/imports/exports disappear. Every remaining form has
    // one output form in the same order; preserve its source/call-site span.
    var outputIndex = 0;
    for (form in forms) {
      var directive = switch (form) {
        case Define(name, _): StringTools.startsWith(name, MacroExpander.DECL)
          || StringTools.startsWith(name, MacroExpander.IMPORT)
          || StringTools.startsWith(name, MacroExpander.EXPORT);
        case _: false;
      };
      if (!directive) provenance.transfer(form, expanded[outputIndex++]);
    }
    return expanded;
  }

  public function parseRaw():Array<Form> {
    var forms:Array<Form> = [];
    while (peek() != null) {
      var first = at;
      // v0.49 relations have an arbitrary positive arity (last type is
      // the return type). Declarations are compile-time metadata only.
      if (numeric.LanguageVersion.hasGeneralRelations(languageVersion) && at + 1 < tokens.length
          && tokens[at + 1] == ':' &&
          ~/^[A-Z][A-Za-z0-9_]*$/.match(peek())) {
        var relation=take();
        expect(':');
        var row:Array<String>=[];
        while (peek() != ';' && peek() != null) {
          if (row.length > nail.TypeRelation.MAX_ARITY + 1)
            throw 'Type relation: too many types';
          row.push(take());
        }
        expect(';');
        nail.TypeRelation.parseRow(row);
        var found=generalRows.get(relation);
        if (found == null) found=[];
        if (found.length >= nail.TypeRelation.MAX_ROWS)
          throw 'Type relation: too many rows';
        found.push(row);
        generalRows.set(relation,found);
        continue;
      }
      // Legacy finite binary arithmetic relation rows remain unchanged.
      if (modernMode && ['Div','Add','Sub','Mul'].indexOf(peek()) >= 0
          && at + 1 < tokens.length && tokens[at + 1] == ':') {
        var relation = take();
        if (relation != 'Div' && languageVersion == '0.45')
          throw 'Type relation: ' + relation + ' requires Nail 0.46';
        expect(':');
        var left = take(), right = take(), output = take();
        expect(';');
        var previous = relation == 'Div' ? declaredDivRows
          : declaredOperatorRows.get(relation);
        if (previous == null) previous = [];
        numeric.NumericRelation.requireModernRow(
          left,right,output,previous,relation);
        previous.push({left:left,right:right,result:output});
        if (relation != 'Div') declaredOperatorRows.set(relation,previous);
        continue;
      }
      if (peek() == 'type') {
        take();
        var typeName = take();
        if (!isName(typeName) || !recordTypePattern.match(typeName)) throw 'Expected uppercase record type name or sum type';
        var cursor = at;
        while (cursor < tokens.length && tokens[cursor] != '{' &&
            tokens[cursor] != '=' && tokens[cursor] != ';') cursor++;
        forms.push(cursor < tokens.length && tokens[cursor] == '{'
          ? parseRecordType(typeName) : parseSumType(typeName));
      } else if (peek() == 'import' || peek() == 'export') {
        var importing = take() == 'import';
        var name = take();
        if (!isName(name)) throw 'Expected macro name';
        var module:Expr = Literal(Nil);
        if (importing) {
          expect('from');
          var label = take();
          if (!isName(label)) throw 'Expected macro module name';
          module = Var(label);
        }
        expect(';');
        forms.push(Define((importing ? MacroExpander.IMPORT : MacroExpander.EXPORT) + name, module));
      } else if (peek() == 'def' || peek() == 'macro') {
        var macroDeclaration = take() == 'macro';
        var name = take();
        if (!isName(name)) throw 'Expected definition name';
        var params:Array<String> = [];
        var positions:Array<Int> = [];

        while (peek() != '=' && peek() != ':') {
          var atParameter = at;
          var p = take();
          if (!isName(p) || params.indexOf(p) >= 0)
            throw 'Invalid or duplicate definition parameter';
          params.push(p);
          positions.push(atParameter);
        }
        if (peek() == ':') {
          take();
          var relation = take();
          if (!modernMode && (macroDeclaration || params.length != 2 ||
              relation != 'Div'))
            throw 'Type relation: only binary Div declarations are supported';
          if (numeric.LanguageVersion.hasGeneralRelations(languageVersion)) {
            if (macroDeclaration || params.length < 1 ||
                params.length > nail.TypeRelation.MAX_ARITY ||
                !~/^[A-Z][A-Za-z0-9_]*$/.match(relation))
              throw 'Type relation: expected 1 to 16 parameters and named constraint';
          } else if (modernMode && (macroDeclaration || params.length != 2 ||
              ['Div','Add','Sub','Mul'].indexOf(relation) < 0))
            throw 'Type relation: only binary Div/Add/Sub/Mul declarations are supported';
          if (modernMode && relation != 'Div' && languageVersion == '0.45')
            throw 'Type relation: ' + relation + ' requires Nail 0.46';
          if (exactMode)
            throw 'Type relation: exact source dialect is not supported yet';
          declaredRelations.set(name, numeric.LanguageVersion.hasGeneralRelations(languageVersion)
            ? relation : modernMode
            ? numeric.NumericRelation.modernName(relation) : relation);
        }
        expect('=');
        var body = lambdas(params, expression(), positions);
        expect(';');
        forms.push(Define(macroDeclaration ? MacroExpander.DECL + name : name, body));
      } else {
        var body = expression(); expect(';'); forms.push(Evaluate(body));
      }
      provenance.form(forms[forms.length - 1], first, at);
    }
    return forms;
  }
}

