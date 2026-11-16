package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;

/** Whitespace-delimited lexer + small precedence parser, with desugaring to Expr. */
class Parser {
  final tokens:Array<String>;
  var at:Int = 0;

  static final namePattern = ~/^[A-Za-z_][A-Za-z_0-9]*$/;
  static final recordTypePattern = ~/^[A-Z][A-Za-z_0-9]*$/;
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
      case 'def' | 'type' | 'if' | 'then' | 'else' | 'fun' | 'true' | 'false' | 'let' | 'in' | 'match' | 'with': false;
      case _: true;
    };
  }

  static function isNumber(s:Null<String>):Bool return s != null && numberPattern.match(s);

  static function beginsAtom(s:Null<String>):Bool {
    return switch (s) {
      case '(' | '[' | '[]' | 'fun' | 'if' | 'let' | 'match' | 'true' | 'false': true;
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

  function atom():Expr {
    var token = take();
    if (token == null) throw 'Unexpected end of input';
    if (StringTools.startsWith(token, '\u0001')) return Literal(Text(token.substr(1)));
    if (token == '[]') return Literal(Nil);
    if (token == '(') {
      // Collapse runs of redundant grouping before descending once into
      // expression(). The remaining Pratt/parser nesting is still recursive.
      var depth = 1;
      while (peek() == '(') { take(); depth++; }
      var inner = expression();
      while (depth > 0) { expect(')'); depth--; }
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

  function expression(minimum:Int = 0):Expr {
    var left = atom();
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
  function parseRecordType():Form {
    var typeName = take();
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

  public function parse():Array<Form> {
    var forms:Array<Form> = [];
    while (peek() != null) {
      if (peek() == 'type') {
        take();
        forms.push(parseRecordType());
      } else if (peek() == 'def') {
        take();
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
        forms.push(Define(name, body));
      } else {
        var body = expression(); expect(';'); forms.push(Evaluate(body));
      }
    }
    return forms;
  }
}
