package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;

/** Whitespace-delimited lexer + small precedence parser, with desugaring to Expr. */
class Parser {
  final tokens:Array<String>;
  var at:Int = 0;

  static final namePattern = ~/^[A-Za-z_][A-Za-z_0-9]*$/;
  static final numberPattern = ~/^-?(?:\d+(?:\.\d+)?|\.\d+)$/;
  static final commentPattern = ~/(^|\s)#.*$/;
  static final spacePattern = ~/\s+/g;

  public function new(source:String) {
    var lines:Array<String> = [];
    for (line in source.split('\n')) lines.push(commentPattern.replace(line, '$1'));
    var clean = StringTools.trim(lines.join(' '));
    tokens = clean == '' ? [] : spacePattern.split(clean);
  }

  static function isName(s:Null<String>):Bool {
    if (s == null || !namePattern.match(s)) return false;
    return switch (s) {
      case 'def' | 'if' | 'then' | 'else' | 'fun' | 'true' | 'false': false;
      case _: true;
    };
  }

  static function isNumber(s:Null<String>):Bool return s != null && numberPattern.match(s);

  static function beginsAtom(s:Null<String>):Bool {
    return switch (s) {
      case '(' | '[' | '[]' | 'fun' | 'if' | 'true' | 'false': true;
      case _: isName(s) || isNumber(s);
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

  function atom():Expr {
    var token = take();
    if (token == null) throw 'Unexpected end of input';
    if (token == '[]') return Literal(Nil);
    if (token == '(') {
      var inner = expression(); expect(')'); return inner;
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

  public function parse():Array<Form> {
    var forms:Array<Form> = [];
    while (peek() != null) {
      if (peek() == 'def') {
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
