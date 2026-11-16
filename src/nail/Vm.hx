package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;

/** Explicit evaluator continuations: no recursive host calls for Nail function
    application, including mutually recursive and non-tail source functions. */
private enum EvalFrame {
  NeedArgument(argument:Expr, scope:Env);
  ApplyFunction(fn:Value);
  ChooseBranch(yes:Expr, no:Expr, scope:Env);
}


/** Small, pure Nail evaluator. No JS / PHP target branches. */
class Vm {
  final root:Env;
  final maxSteps:Int;
  var steps:Int = 0;

  public function new(maxSteps:Int = 100000) {
    if (maxSteps <= 0) throw 'maxSteps must be positive';
    this.maxSteps = maxSteps;
    root = new Env();
    for (name in ['+', '-', '*', '/', '<', '<=', '>', '>=', '==', '!=', 'cons', '#cons', 'textAt', 'textConcat', 'syntaxLeaf', 'syntaxNode'])
      root.bind(name, Native(name, 2, []));
    for (name in ['head', 'tail', 'isEmpty', '#head', '#tail', '#isEmpty', 'textLength', 'syntaxTag', 'syntaxText', 'syntaxChildren']) root.bind(name, Native(name, 1, []));
    root.bind('nil', Nil);
  }

  inline function tick():Void {
    steps++;
    if (steps > maxSteps) throw 'Execution budget exceeded';
  }

  static function number(v:Value):Float {
    return switch (v) {
      case Number(n): if (!Math.isFinite(n)) throw 'Expected finite number' else n;
      case _: throw 'Expected finite number';
    };
  }

  static function bool(v:Value):Bool {
    return switch (v) {
      case Boolean(b): b;
      case _: throw 'Expected boolean';
    };
  }

  static function text(v:Value):String {
    return switch (v) {
      case Text(s):
        // Source processing is ASCII-only for now, making Haxe's indexing
        // consistent across JS UTF-16 and PHP's string implementation.
        for (i in 0...s.length) if (s.charCodeAt(i) > 127) throw 'Expected ASCII text';
        s;
      case _: throw 'Expected text';
    };
  }

  static function index(v:Value, size:Int):Int {
    var n = number(v);
    if (n < 0 || n >= size || n != Math.floor(n)) throw 'Text index out of range';
    return Std.int(n);
  }

  static function finite(n:Float):Value {
    if (!Math.isFinite(n)) throw 'Nonfinite arithmetic result';
    return Number(n);
  }

  static function equal(a:Value, b:Value):Bool {
    return switch ([a, b]) {
      case [Number(x), Number(y)]: x == y;
      case [Boolean(x), Boolean(y)]: x == y;
      case [Text(x), Text(y)]: x == y;
      case [SyntaxLeaf(tx, x), SyntaxLeaf(ty, y)]: tx == ty && x == y;
      case [SyntaxNode(tx, xs), SyntaxNode(ty, ys)]: tx == ty && equal(xs, ys);
      case [Nil, Nil]: true;
      case [Cons(x, xs), Cons(y, ys)]: equal(x, y) && equal(xs, ys);
      case [Nil, Cons(_, _)] | [Cons(_, _), Nil]: false;
      case _: throw 'Cannot compare these values';
    };
  }

  static function syntax(v:Value):Value {
    return switch (v) {
      case SyntaxLeaf(_, _) | SyntaxNode(_, _): v;
      case _: throw 'Expected Syntax';
    };
  }

  static function syntaxList(v:Value):Value {
    var rest = v;
    while (true) {
      switch (rest) {
        case Nil: return v;
        case Cons(item, tail): syntax(item); rest = tail;
        case _: throw 'Expected Syntax list';
      }
    }
    return v;
  }

  public static function primitive(name:String, args:Array<Value>):Value {
    var a = args[0];
    var b = args.length > 1 ? args[1] : Nil;
    return switch (name) {
      case '+': finite(number(a) + number(b));
      case '-': finite(number(a) - number(b));
      case '*': finite(number(a) * number(b));
      case '/':
        var divisor = number(b);
        if (divisor == 0) throw 'Division by zero';
        finite(number(a) / divisor);
      case '<': Boolean(number(a) < number(b));
      case '<=': Boolean(number(a) <= number(b));
      case '>': Boolean(number(a) > number(b));
      case '>=': Boolean(number(a) >= number(b));
      case '==': Boolean(equal(a, b));
      case '!=': Boolean(!equal(a, b));
      case 'textLength': Number(text(a).length);
      case 'textAt':
        var source = text(a);
        Text(source.charAt(index(b, source.length)));
      case 'textConcat': Text(text(a) + text(b));
      case 'syntaxLeaf': SyntaxLeaf(text(a), text(b));
      case 'syntaxNode': SyntaxNode(text(a), syntaxList(b));
      case 'syntaxTag': switch (syntax(a)) {
        case SyntaxLeaf(tag, _) | SyntaxNode(tag, _): Text(tag);
        case _: throw 'Expected Syntax';
      };
      case 'syntaxText': switch (syntax(a)) {
        case SyntaxLeaf(_, value): Text(value);
        case _: throw 'Expected syntax leaf';
      };
      case 'syntaxChildren': switch (syntax(a)) {
        case SyntaxNode(_, children): children;
        case _: throw 'Expected syntax node';
      };
      case 'cons' | '#cons':
        switch (b) {
          case Nil | Cons(_, _): Cons(a, b);
          case _: throw 'Expected list';
        }
      case 'isEmpty' | '#isEmpty':
        switch (a) {
          case Nil: Boolean(true);
          case Cons(_, _): Boolean(false);
          case _: throw 'Expected list';
        }
      case 'head' | '#head':
        switch (a) {
          case Cons(x, _): x;
          case Nil: throw 'head of empty list';
          case _: throw 'Expected list';
        }
      case 'tail' | '#tail':
        switch (a) {
          case Cons(_, xs): xs;
          case Nil: throw 'tail of empty list';
          case _: throw 'Expected list';
        }
      case _: throw 'Unknown primitive: ' + name;
    };
  }

  /** Host-stack independent CEK-style evaluator. Nested applications and
      branches use heap continuations rather than recursive host calls. */
  function evaluate(expr:Expr, env:Env):Value {
    var current:Expr = expr;
    var scope:Env = env;
    var result:Value = Nil;
    var hasResult = false;
    var frames:Array<EvalFrame> = [];
    while (true) {
      tick();
      if (!hasResult) {
        switch (current) {
          case Literal(v): result = v; hasResult = true;
          case Var(name): result = scope.lookup(name); hasResult = true;
          case Lambda(param, body): result = Closure(param, body, scope); hasResult = true;
          case Apply(fn, arg):
            frames.push(NeedArgument(arg, scope));
            current = fn;
          case If(condition, yes, no):
            frames.push(ChooseBranch(yes, no, scope));
            current = condition;
        }
      } else {
        if (frames.length == 0) return result;
        switch (frames.pop()) {
          case NeedArgument(arg, captured):
            frames.push(ApplyFunction(result));
            current = arg;
            scope = captured;
            hasResult = false;
          case ChooseBranch(yes, no, captured):
            current = bool(result) ? yes : no;
            scope = captured;
            hasResult = false;
          case ApplyFunction(fn):
            tick();
            switch (fn) {
              case Closure(param, body, captured):
                var local = new Env(captured);
                local.bind(param, result);
                current = body;
                scope = local;
                hasResult = false;
              case Native(name, arity, prior):
                var args = prior.copy();
                args.push(result);
                result = args.length < arity ? Native(name, arity, args) : primitive(name, args);
              case _: throw 'Value is not a function';
            }
        }
      }
    }
    throw 'Unreachable iterative evaluator';
  }

  /** The self-hosted parser/compiler use the same iterative evaluation path. */
  function call(f:Value, arg:Value):Value {
    return evaluate(Apply(Literal(f), Literal(arg)), root);
  }

  /** Execute validated core forms using the same evaluator on every target. */
  function executeForms(forms:Array<Form>):Array<Value> {
    var output:Array<Value> = [];
    for (form in forms) {
      switch (form) {
        case Define(name, body):
          if (root.hasHere(name)) throw 'Already defined: ' + name;
          var value = evaluate(body, root);
          root.bind(name, value);
        case Evaluate(body): output.push(evaluate(body, root));
      }
    }
    return output;
  }

  public function run(source:String):Array<Value> {
    steps = 0;
    return executeForms(new Parser(source).parse());
  }

  /** Execute a first-class Syntax Program built by code running in Nail. */
  public function runSyntax(tree:Value):Array<Value> {
    steps = 0;
    return executeForms(SyntaxBridge.forms(tree));
  }

  /** Parse source with the tokenizer and Pratt parser written in Nail. */
  public function parseWithNail(source:String):Value {
    steps = 0;
    return call(root.lookup('parseSource'), Text(source));
  }

  /** Use Nail's own parseSource function, then execute its output.
      The bootstrap Haxe parser is used only to load stdlib.nail. */
  public function runWithNail(source:String):Array<Value> {
    var tree = parseWithNail(source);
    return executeForms(SyntaxBridge.forms(tree));
  }

  public function runPlainWithNail(source:String):Array<Dynamic> return plainResults(runWithNail(source));

  /** Shared primitive environment for a bytecode executor; no source parsing. */
  public function bytecodeRoot():Env return root;

  /** Compile source using the compiler function written in Nail. */
  public function compileWithNail(source:String):Value {
    steps = 0;
    return call(root.lookup('compileSource'), Text(source));
  }

  /** Compile an already-parsed Syntax program using Nail code only.
      Used to bootstrap the compiler without hitting the recursive lexer limit. */
  public function compileSyntaxWithNail(tree:Value):Value {
    steps = 0;
    return call(root.lookup('compileSyntax'), tree);
  }

  public function names():Array<String> return root.keys();

  public function loadStdlib():Void {
    var source = haxe.Resource.getString('stdlib');
    if (source == null) throw 'Missing stdlib resource';
    run(source);
  }

  /** Values converted into JSON-compatible primitive data (functions intentionally excluded). */
  public static function toPlain(value:Value):Dynamic {
    return switch (value) {
      case Number(n): n;
      case Boolean(b): b;
      case Text(s): s;
      case SyntaxLeaf(kind, value): {tag:kind, value:value};
      case SyntaxNode(kind, children): {tag:kind, children:toPlain(children)};
      case Nil: ([] : Array<Dynamic>);
      case Cons(_, _):
        var items:Array<Dynamic> = [];
        var rest = value;
        var complete = false;
        while (!complete) {
          switch (rest) {
            case Nil: complete = true;
            case Cons(head, tail): items.push(toPlain(head)); rest = tail;
            case _: throw 'Malformed list';
          }
        }
        items;
      case _: throw 'Cannot serialize function value';
    };
  }

  /** Public convenience API, usable from the generated JS runtime. */
  public function runPlain(source:String):Array<Dynamic> return plainResults(run(source));

  public static function plainResults(values:Array<Value>):Array<Dynamic> {
    return [for (v in values) toPlain(v)];
  }
}
