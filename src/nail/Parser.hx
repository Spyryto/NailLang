package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;
import nail.SumLowering;

/** Whitespace-delimited lexer + small precedence parser, with desugaring to Expr. */
class Parser {
  final tokens:Array<String>;
  var at:Int = 0;

  static final namePattern = ~/^[A-Za-z_][A-Za-z_0-9]*$/;
  static final recordTypePattern = ~/^[A-Z][A-Za-z_0-9]*$/;
  static final typeParamPattern = ~/^[a-z][a-z0-9_]*$/;
  static final numberPattern = ~/^-?(?:\d+(?:\.\d+)?|\.\d+)$/;
  static final spacePattern = ~/\s+/g;

  public function new(source:String) {
    tokens = tokenizeHost(source);
  }

  // String boundaries are separate whitespace-delimited tokens: " hello world ".
  // Contents are joined with one space and decoded as JSON string escapes.
  // Comments are ignored outside quoted text only.
  static function tokenizeHost(source:String):Array<String> {
    var result:Array<String> = [];
    var quoted = false;
    var parts:Array<String> = [];
    for (line in source.split('\n')) {
      var clean = StringTools.trim(line);
      var words = clean == '' ? [] : spacePattern.split(clean);
      for (word in words) {
        if (quoted) {
          if (word == '"') {
            var value:String;
            try value = haxe.Json.parse('"' + parts.join(' ') + '"')
            catch (e:Dynamic) throw 'Invalid string escape: ' + Std.string(e);
            result.push('\u0001' + value);
            parts = [];
            quoted = false;
          } else parts.push(word);
        } else if (StringTools.startsWith(word, '#')) {
          break;
        } else if (word == '"') {
          quoted = true;
          parts = [];
        } else result.push(word);
      }
    }
    if (quoted) throw 'Unterminated string literal';
    return result;
  }

  static function isName(s:Null<String>):Bool {
    if (s == null || !namePattern.match(s)) return false;
    return switch (s) {
      case 'macro' | 'quote' | 'unquote' | 'expand' | 'def' | 'type' | 'if' | 'then' | 'else' | 'fun' | 'true' | 'false' | 'let' | 'in' | 'match' | 'with': false;
      case _: true;
    };
  }

  static function isNumber(s:Null<String>):Bool return s != null && numberPattern.match(s);

  static function beginsAtom(s:Null<String>):Bool {
    return switch (s) {
      case 'quote' | 'unquote' | 'expand' | '(' | '[' | '[]' | 'fun' | 'if' | 'let' | 'match' | 'true' | 'false': true;
      case _: (s != null && StringTools.startsWith(s, '\u0001')) || isName(s) || isNumber(s);
    };
  }

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

  static function lambdas(params:Array<String>, body:Expr):Expr {
    var result = body;
    var i = params.length;
    while (i > 0) { i--; result = Lambda(params[i], result); }
    return result;
  }

  /** Internal names cannot be written in source. Fixed names are safe here:
      each lowered list match introduces its own lexical lambda scope. This
      matches the pure Nail-written lowering and makes bytecode reproducible. */
  function hidden(label:String):String return '#nail_' + label + '_0';

  /** Surface let: ( fun name -> body ) value. A non-recursive, eager binding. */
  function parseLet():Expr {
    var name = take();
    if (!isName(name) || name == '_') throw 'Invalid let binding name';
    expect('=');
    var value = expression();
    expect('in');
    var body = expression();
    return Apply(Lambda(name, body), value);
  }

  /** Exactly two exhaustive list patterns, [] and head :: tail, in either order.
      Core only sees if/lam/apply; the input is evaluated exactly once. */
  function parseMatch():Expr {
    var scrutinee = expression();
    expect('with');
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
        payload.push(ty);
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

  function atom():Expr {
    var token = take();
    if (token == null) throw 'Unexpected end of input';
    if (StringTools.startsWith(token, '\u0001')) return Literal(Text(token.substr(1)));
    if (token == 'quote' || token == 'unquote' || token == 'expand') return Var('#macro_' + token);
    if (token == '[]') return Literal(Nil);
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
    if (token == 'if') {
      var condition = expression(); expect('then');
      var yes = expression(); expect('else');
      return If(condition, yes, expression());
    }
    if (token == 'fun') {
      var params:Array<String> = [];
      while (peek() != '->') {
        var p = take();
        if (!isName(p) || params.indexOf(p) >= 0) throw 'Invalid or duplicate function parameter';
        params.push(p);
      }
      if (params.length == 0) throw 'Function needs at least one parameter';
      expect('->');
      return lambdas(params, expression());
    }
    if (isNumber(token)) {
      var number = Std.parseFloat(token);
      if (!Math.isFinite(number)) throw 'Number out of range: ' + token;
      return Literal(Number(number));
    }
    if (token == 'true' || token == 'false') return Literal(Boolean(token == 'true'));
    if (isName(token)) return Var(token);
    throw 'Unexpected token ' + token + ' at token ' + at;
  }

  function expression(minimum:Int = 0):Expr return expressionSuffix(atom(), minimum);

  function expressionSuffix(left:Expr, minimum:Int):Expr {
    while (peek() != null) {
      // Projection is explicit; binding power 80 (higher than application).
      if (peek() == '.' && minimum <= 80) {
        take();
        var field = take();
        if (!isName(field) || field == '_') throw 'Expected record field after .';
        left = Apply(Apply(Var('#recordGet'), left), Literal(Text(field)));
        continue;
      }
      if (beginsAtom(peek()) && minimum <= 70) {
        left = Apply(left, expression(71));
        continue;
      }
      var prec = precedence(peek());
      if (prec < minimum) break;
      var op = take();
      left = Apply(Apply(Var(op), left), expression(prec + 1));
    }
    return left;
  }

  /** Only simple named fields and previously declared record types in v0.17. */
  function parseRecordType(typeName:String):Form {
    if (!isName(typeName) || !recordTypePattern.match(typeName))
      throw 'Expected uppercase record type name';
    expect('{');
    var fields:Array<nail.Ast.RecordField> = [];
    while (peek() != '}') {
      var fieldName = take();
      if (!isName(fieldName) || fieldName == '_') throw 'Expected record field name';
      var fieldType = take();
      if (!isName(fieldType)) throw 'Expected record field type';
      for (item in fields) if (item.name == fieldName) throw 'Duplicate record field ' + fieldName;
      fields.push({name:fieldName, typeName:fieldType});
      if (fields.length > 128) throw 'Too many record fields';
    }
    expect('}');
    expect(';');
    if (fields.length == 0) throw 'Record requires at least one field';
    return RecordType(typeName, fields);
  }

  public function parse():Array<Form> return MacroExpander.forms(parseRaw());

  public function parseRaw():Array<Form> {
    var forms:Array<Form> = [];
    while (peek() != null) {
      if (peek() == 'type') {
        take();
        var typeName = take();
        if (!isName(typeName) || !recordTypePattern.match(typeName)) throw 'Expected uppercase record type name or sum type';
        forms.push(peek() == '{' ? parseRecordType(typeName) : parseSumType(typeName));
      } else if (peek() == 'def' || peek() == 'macro') {
        var macroDeclaration = take() == 'macro';
        var name = take();
        if (!isName(name)) throw 'Expected definition name';
        var params:Array<String> = [];
        while (peek() != '=') {
          var p = take();
          if (!isName(p) || params.indexOf(p) >= 0) throw 'Invalid or duplicate definition parameter';
          params.push(p);
        }
        expect('=');
        var body = lambdas(params, expression());
        expect(';');
        forms.push(Define(macroDeclaration ? MacroExpander.DECL + name : name, body));
      } else {
        var body = expression(); expect(';'); forms.push(Evaluate(body));
      }
    }
    return forms;
  }
}

