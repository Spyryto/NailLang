package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;

/** Whitespace-delimited lexer + small precedence parser, with desugaring to Expr. */
class Parser {
  final tokens:Array<String>;
  var at:Int = 0;
  var generated:Int = 0;

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
      case 'def' | 'if' | 'then' | 'else' | 'fun' | 'true' | 'false' | 'let' | 'in' | 'match' | 'with': false;
      case _: true;
    };
  }

  static function isNumber(s:Null<String>):Bool return s != null && numberPattern.match(s);

  static function beginsAtom(s:Null<String>):Bool {
    return switch (s) {
      case '(' | '[' | '[]' | 'fun' | 'if' | 'let' | 'match' | 'true' | 'false': true;
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

  /** Internal names cannot be expressed as user tokens, preventing variable capture. */
  function hidden(label:String):String return '#nail_' + label + '_' + (generated++);

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
