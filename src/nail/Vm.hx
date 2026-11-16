package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;

/** Small, pure Nail evaluator. No JS / PHP target branches. */
class Vm {
  final root:Env;
  final maxSteps:Int;
  var steps:Int = 0;

  public function new(maxSteps:Int = 100000) {
    if (maxSteps <= 0) throw 'maxSteps must be positive';
    this.maxSteps = maxSteps;
    root = new Env();
    for (name in ['+', '-', '*', '/', '<', '<=', '>', '>=', '==', '!=', 'cons', '#cons'])
      root.bind(name, Native(name, 2, []));
    for (name in ['head', 'tail', 'isEmpty', '#head', '#tail', '#isEmpty']) root.bind(name, Native(name, 1, []));
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

  static function finite(n:Float):Value {
    if (!Math.isFinite(n)) throw 'Nonfinite arithmetic result';
    return Number(n);
  }

  static function equal(a:Value, b:Value):Bool {
    return switch ([a, b]) {
      case [Number(x), Number(y)]: x == y;
      case [Boolean(x), Boolean(y)]: x == y;
      case [Nil, Nil]: true;
      case [Cons(x, xs), Cons(y, ys)]: equal(x, y) && equal(xs, ys);
      case [Nil, Cons(_, _)] | [Cons(_, _), Nil]: false;
      case _: throw 'Cannot compare these values';
    };
  }

  static function primitive(name:String, args:Array<Value>):Value {
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

  function call(f:Value, arg:Value):Value {
    tick();
    return switch (f) {
      case Closure(param, body, captured):
        var child = new Env(captured);
        child.bind(param, arg);
        evaluate(body, child);
      case Native(name, arity, prior):
        var args = prior.copy();
        args.push(arg);
        if (args.length < arity) Native(name, arity, args) else primitive(name, args);
      case _: throw 'Value is not a function';
    };
  }

  function evaluate(expr:Expr, env:Env):Value {
    tick();
    return switch (expr) {
      case Literal(v): v;
      case Var(name): env.lookup(name);
      case Lambda(param, body): Closure(param, body, env);
      case Apply(f, x): call(evaluate(f, env), evaluate(x, env));
      case If(condition, yes, no): evaluate(bool(evaluate(condition, env)) ? yes : no, env);
    };
  }

  public function run(source:String):Array<Value> {
    var output:Array<Value> = [];
    steps = 0;
    for (form in new Parser(source).parse()) {
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
