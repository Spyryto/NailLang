package nail;

import nail.Value;

/** Minimal structured stack-bytecode executor.
    Instructions are encoded as first-class SyntaxNode values, so a Nail
    program can emit and compose them without special compiler host APIs.
    The runtime shares the exact same primitive implementations as the AST VM. */
class ByteVm {
  final globals:Env;
  final maxSteps:Int;
  var steps:Int = 0;

  public function new(maxSteps:Int = 100000) {
    if (maxSteps <= 0) throw 'maxSteps must be positive';
    this.maxSteps = maxSteps;
    globals = new Vm(maxSteps).bytecodeRoot();
  }

  function tick():Void {
    if (++steps > maxSteps) throw 'Bytecode execution budget exceeded';
  }

  static function elements(value:Value):Array<Value> {
    var result:Array<Value> = [];
    var rest = value;
    while (true) {
      switch (rest) {
        case Nil: return result;
        case Cons(head, tail): result.push(head); rest = tail;
        case _: throw 'Invalid bytecode: expected list';
      }
    }
    return result;
  }

  static function operands(value:Value, tag:String, arity:Int):Array<Value> {
    return switch (value) {
      case SyntaxNode(t, children) if (t == tag):
        var items = elements(children);
        if (arity >= 0 && items.length != arity) throw 'Invalid bytecode arity: ' + tag;
        items;
      case _: throw 'Invalid bytecode: expected ' + tag;
    };
  }

  static function label(value:Value, tag:String):String {
    return switch (value) {
      case SyntaxLeaf(actual, name) if (actual == tag): name;
      case _: throw 'Invalid bytecode: expected ' + tag + ' operand';
    };
  }

  static function literal(value:Value):Value {
    return switch (SyntaxBridge.expr(value)) {
      case nail.Ast.Expr.Literal(v): v;
      case _: throw 'Invalid bytecode: CONST needs a literal';
    };
  }

  static function pop(stack:Array<Value>):Value {
    if (stack.length == 0) throw 'Bytecode stack underflow';
    return stack.pop();
  }

  function call(fn:Value, value:Value):Value {
    tick();
    return switch (fn) {
      case ByteClosure(param, body, captured):
        var local = new Env(captured);
        local.bind(param, value);
        executeCode(body, local, true);
      case Native(name, arity, applied):
        var args = applied.copy();
        args.push(value);
        if (args.length < arity) Native(name, arity, args)
        else Vm.primitive(name, args);
      case _: throw 'Bytecode value is not callable';
    };
  }

  function executeCode(block:Value, env:Env, needsReturn:Bool):Value {
    var statements = operands(block, 'Code', -1);
    // Code has variable arity; decode its children directly, rather than
    // treating the instruction count as fixed.
    return executeInstructions(statements, env, needsReturn);
  }

  function executeInstructions(instructions:Array<Value>, env:Env, needsReturn:Bool):Value {
    var stack:Array<Value> = [];
    for (instruction in instructions) {
      tick();
      switch (instruction) {
        case SyntaxNode('CONST', _):
          var args = operands(instruction, 'CONST', 1);
          stack.push(literal(args[0]));
        case SyntaxNode('LOAD', _):
          var args = operands(instruction, 'LOAD', 1);
          stack.push(env.lookup(label(args[0], 'Var')));
        case SyntaxNode('CLOSURE', _):
          var args = operands(instruction, 'CLOSURE', 2);
          stack.push(ByteClosure(label(args[0], 'Name'), args[1], env));
        case SyntaxNode('CALL', _):
          operands(instruction, 'CALL', 0);
          var arg = pop(stack);
          var fn = pop(stack);
          stack.push(call(fn, arg));
        case SyntaxNode('BRANCH', _):
          var args = operands(instruction, 'BRANCH', 2);
          var condition = pop(stack);
          var yes = switch (condition) {
            case Boolean(value): value;
            case _: throw 'Expected boolean';
          };
          stack.push(executeCode(yes ? args[0] : args[1], env, false));
        case SyntaxNode('RETURN', _):
          operands(instruction, 'RETURN', 0);
          if (stack.length != 1) throw 'Invalid bytecode return stack depth';
          return pop(stack);
        case SyntaxNode(tag, _): throw 'Unknown opcode: ' + tag;
        case _: throw 'Invalid bytecode instruction';
      }
    }
    if (needsReturn) throw 'Invalid bytecode: missing RETURN';
    if (stack.length != 1) throw 'Invalid bytecode block stack depth';
    return pop(stack);
  }

  public function run(program:Value):Array<Value> {
    steps = 0;
    var output:Array<Value> = [];
    for (form in operands(program, 'Bytecode', -1)) {
      tick();
      switch (form) {
        case SyntaxNode('DEFINE', _):
          var xs = operands(form, 'DEFINE', 2);
          var name = label(xs[0], 'Name');
          if (globals.hasHere(name)) throw 'Already defined: ' + name;
          globals.bind(name, executeCode(xs[1], globals, true));
        case SyntaxNode('EVAL', _):
          var xs = operands(form, 'EVAL', 1);
          output.push(executeCode(xs[0], globals, true));
        case SyntaxNode(tag, _): throw 'Unknown bytecode form: ' + tag;
        case _: throw 'Invalid bytecode program form';
      }
    }
    return output;
  }

  /** Use a bytecode-compiled Nail compiler on an already parsed Syntax AST. */
  public function compileSyntax(tree:Value):Value {
    steps = 0;
    return call(globals.lookup('compileSyntax'), tree);
  }

  public function compileSource(source:String):Value {
    steps = 0;
    return call(globals.lookup('compileSource'), Text(source));
  }

  public function names():Array<String> return globals.keys();
  public function runPlain(program:Value):Array<Dynamic> return Vm.plainResults(run(program));
}
