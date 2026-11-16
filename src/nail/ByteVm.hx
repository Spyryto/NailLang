package nail;

import nail.Value;

/** Saved interpreter activation. Both non-tail CALL and non-tail BRANCH use
    this explicit heap frame instead of a recursive Haxe/JS/PHP invocation. */
private typedef ByteFrame = {
  var code:Array<Value>;
  var next:Int;
  var env:Env;
  var stack:Array<Value>;
  var needsReturn:Bool;
}

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

  /** A complete iterative executor. Ordinary calls and non-tail branches
      save a heap frame; TAIL_CALL replaces the active code/environment and
      *does not* push a frame. Even deeply nested non-tail programs therefore
      cannot overflow the host language's call stack. */
  function executeCode(block:Value, initial:Env, mustReturn:Bool):Value {
    var code = operands(block, 'Code', -1);
    var pc = 0;
    var env = initial;
    var stack:Array<Value> = [];
    var needsReturn = mustReturn;
    var frames:Array<ByteFrame> = [];
    var delivering = false;
    var completed:Value = Nil;

    while (true) {
      if (delivering) {
        if (frames.length == 0) return completed;
        var saved = frames.pop();
        code = saved.code;
        pc = saved.next;
        env = saved.env;
        stack = saved.stack;
        needsReturn = saved.needsReturn;
        stack.push(completed);
        delivering = false;
        continue;
      }
      if (pc >= code.length) {
        if (needsReturn) throw 'Invalid bytecode: missing RETURN';
        if (stack.length != 1) throw 'Invalid bytecode block stack depth';
        completed = pop(stack);
        delivering = true;
        continue;
      }
      var instruction = code[pc++];
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
        case SyntaxNode('CALL', _) | SyntaxNode('TAIL_CALL', _):
          var tail = switch (instruction) {
            case SyntaxNode('TAIL_CALL', _): true;
            case _: false;
          };
          operands(instruction, tail ? 'TAIL_CALL' : 'CALL', 0);
          if (tail && (!needsReturn || pc != code.length))
            throw 'Invalid bytecode: TAIL_CALL outside tail position';
          var arg = pop(stack);
          var fn = pop(stack);
          if (tail && stack.length != 0) throw 'Invalid bytecode tail-call stack depth';
          tick(); // Count calls in addition to instruction fetches.
          switch (fn) {
            case ByteClosure(param, body, captured):
              if (!tail) frames.push({code:code, next:pc, env:env, stack:stack, needsReturn:needsReturn});
              var local = new Env(captured);
              local.bind(param, arg);
              code = operands(body, 'Code', -1);
              pc = 0;
              env = local;
              stack = [];
              needsReturn = true;
            case Native(name, arity, applied):
              var all = applied.copy();
              all.push(arg);
              var value = all.length < arity ? Native(name, arity, all) : Vm.primitive(name, all);
              if (tail) {
                completed = value;
                delivering = true;
              } else stack.push(value);
            case HostFunction(_, invoke):
              var value = invoke(arg);
              if (tail) {
                completed = value;
                delivering = true;
              } else stack.push(value);
            case _: throw 'Bytecode value is not callable';
          }
        case SyntaxNode('BRANCH', _):
          var args = operands(instruction, 'BRANCH', 2);
          var condition = pop(stack);
          var chooseYes = switch (condition) {
            case Boolean(value): value;
            case _: throw 'Expected boolean';
          };
          var tailBranch = needsReturn && pc == code.length;
          if (tailBranch && stack.length != 0) throw 'Invalid bytecode tail-branch stack depth';
          if (!tailBranch) frames.push({code:code, next:pc, env:env, stack:stack, needsReturn:needsReturn});
          code = operands(chooseYes ? args[0] : args[1], 'Code', -1);
          pc = 0;
          stack = [];
          needsReturn = tailBranch;
        case SyntaxNode('RETURN', _):
          operands(instruction, 'RETURN', 0);
          if (pc != code.length) throw 'Invalid bytecode: instructions after RETURN';
          if (stack.length != 1) throw 'Invalid bytecode return stack depth';
          completed = pop(stack);
          delivering = true;
        case SyntaxNode(tag, _): throw 'Unknown opcode: ' + tag;
        case _: throw 'Invalid bytecode instruction';
      }
    }
    throw 'Unreachable iterative bytecode executor';
  }

  /** Entry point used to run a compiled closure outside another bytecode
      program (e.g. compiler.bootstrap). Calls inside it are still iterative. */
  function call(fn:Value, arg:Value):Value {
    tick();
    return switch (fn) {
      case ByteClosure(param, body, captured):
        var env = new Env(captured);
        env.bind(param, arg);
        executeCode(body, env, true);
      case Native(name, arity, applied):
        var args = applied.copy();
        args.push(arg);
        args.length < arity ? Native(name, arity, args) : Vm.primitive(name, args);
      case HostFunction(_, invoke): invoke(arg);
      case _: throw 'Bytecode value is not callable';
    };
  }

  /** Public, budgeted invocation of a compiled Nail function. */
  public function invoke(name:String, argument:Value):Value {
    steps = 0;
    return call(globals.lookup(name), argument);
  }

  /** Execute a top-level expression that may end in TAIL_CALL. */
  function executeTop(block:Value):Value return executeCode(block, globals, true);

  public function run(program:Value):Array<Value> {
    steps = 0;
    var output:Array<Value> = [];
    switch (program) {
      case SyntaxLeaf('MacroError', message): throw 'Macro error: ' + message;
      case _:
    }
    for (form in operands(program, 'Bytecode', -1)) {
      tick();
      switch (form) {
        case SyntaxNode('DEFINE', _):
          var xs = operands(form, 'DEFINE', 2);
          var name = label(xs[0], 'Name');
          if (globals.hasHere(name)) throw 'Already defined: ' + name;
          globals.bind(name, executeTop(xs[1]));
        case SyntaxNode('EVAL', _):
          var xs = operands(form, 'EVAL', 1);
          output.push(executeTop(xs[0]));
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

  public function compileSource(source:String, ?modules:String->Null<String>):Value {
    steps = 0;
    if (modules == null) {

      var compiler = numeric.LanguageVersion.isModern(source) ? 'compileModernSource'
        : numeric.NumericDialect.isExact(source) ? 'compileExactSource' : 'compileSource';
      return call(globals.lookup(compiler), Text(source));
    }
    var parse = globals.lookup('parseSource');
    var expanded = MacroExpander.syntax(call(parse, Text(source)), name -> {
      var moduleSource = modules(name);
      if (moduleSource == null) return null;
      if (numeric.NumericDialect.isExact(moduleSource) != numeric.NumericDialect.isExact(source))
        throw 'Imported macro module uses incompatible numeric dialect: ' + name;
      return call(parse, Text(moduleSource));
    });

    var typed = numeric.LanguageVersion.isModern(source)
      ? call(globals.lookup('modernRewrite'), expanded)
      : numeric.NumericDialect.isExact(source)
      ? call(globals.lookup('exactRewrite'), expanded) : expanded;
    return compileSyntax(typed);
  }

  /** Host-selected capability name; links only a callable and does not
      expose a path, filesystem, or general host-evaluation primitive. */
  public function grantTextReader(alias:String, capability:TextReadCapability):Void {
    if (capability == null) throw 'Missing text reader capability';
    linkImport(alias, capability.asValue());
  }

  /** Opt-in discriminated Result[Text,Text] host read grant. */
  public function grantTextResultReader(alias:String, capability:TextReadCapability):Void {
    if (capability == null) throw 'Missing text reader capability';
    linkImport(alias, capability.asResultValue());
  }

  /** Explicit write-only grant, using the same import alias safeguards. */
  public function grantTextWriter(alias:String, capability:TextWriteCapability):Void {
    if (capability == null) throw 'Missing text writer capability';
    linkImport(alias, capability.asValue());
  }

  /** Link a verified import without altering the compiled module's code.
      A module gets a fresh ByteVm root; only declared exported values are
      installed and ordinary global lookup remains private to that module. */
  public function linkImport(alias:String, value:Value):Void {
    if (!~/^[A-Za-z_][A-Za-z_0-9]*$/.match(alias))
      throw 'Module linker: invalid import alias ' + alias;
    if (globals.hasHere(alias))
      throw 'Module linker: duplicate or reserved import alias ' + alias;
    globals.bind(alias, value);
  }

  /** The linker calls this only after verifying the symbol was explicitly
      exported by the compiled module's own source declarations. */
  public function readExport(name:String):Value {
    if (!globals.hasHere(name))
      throw 'Module linker: missing exported binding ' + name;
    return globals.lookup(name);
  }

  public function names():Array<String> return globals.keys();
  public function runPlain(program:Value):Array<Dynamic> return Vm.plainResults(run(program));
}

