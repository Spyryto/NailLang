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
    root = RuntimePrimitives.environment();
  }


  inline function tick():Void {
    steps++;
    if (steps > maxSteps) throw 'Execution budget exceeded';
  }

  /** Host-stack independent CEK-style evaluator. All nested applications and
      conditional branches use explicit continuation frames, so even the Nail
      lexer/parser can make tens of thousands of recursive calls without
      exhausting the Haxe/JS/PHP call stack. Non-tail source calls may still
      require linear heap space, but never linear host-stack space. */
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
            // Count applications independently from expression visits, as in
            // the recursive v0.11 evaluator. A smaller maxSteps still bounds
            // even an unproductive loop of function applications.
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
                result = args.length < arity ? Native(name, arity, args) : RuntimePrimitives.apply(name, args);
              case HostFunction(_, invoke): result = invoke(result);
              case _: throw 'Value is not a function';
            }
        }
      }
    }
    throw 'Unreachable iterative evaluator';
  }

  /** Run an existing callable, e.g. the Nail-written parser/compiler, through
      the same iterative evaluator. No separate recursive call path exists. */
  function call(f:Value, arg:Value):Value {
    return evaluate(Apply(Literal(f), Literal(arg)), root);
  }

  /** Public, budgeted invocation of an already defined Nail function.
      Used by opt-in procedural transformations of first-class Syntax. */
  public function invoke(name:String, argument:Value):Value {
    steps = 0;
    return call(root.lookup(name), argument);
  }

  /** Only the embedding host can grant this value; Nail has no capability
      constructor or ambient read primitive. Use the same signature with
      TypeChecker.importSignature when checking sources statically. */
  public function grantTextReader(alias:String, capability:TextReadCapability):Void {
    if (capability == null || !~/^[A-Za-z_][A-Za-z_0-9]*$/.match(alias))
      throw 'Invalid text reader grant';
    if (root.hasHere(alias)) throw 'Duplicate or reserved capability alias: ' + alias;
    root.bind(alias, capability.asValue());
  }

  /** Opt-in discriminated Result[Text,Text] host read grant. */
  public function grantTextResultReader(alias:String, capability:TextReadCapability):Void {
    if (capability == null || !~/^[A-Za-z_][A-Za-z_0-9]*$/.match(alias))
      throw 'Invalid text reader grant';
    if (root.hasHere(alias)) throw 'Duplicate or reserved capability alias: ' + alias;
    root.bind(alias, capability.asResultValue());
  }

  /** Explicit write-only grant; separate from every text-reader binding. */
  public function grantTextWriter(alias:String, capability:TextWriteCapability):Void {
    if (capability == null || !~/^[A-Za-z_][A-Za-z_0-9]*$/.match(alias))
      throw 'Invalid text writer grant';
    if (root.hasHere(alias)) throw 'Duplicate or reserved capability alias: ' + alias;
    root.bind(alias, capability.asValue());
  }

  /** Execute core forms through one definition/evaluation path.
      Haxe's declaration lowering remains the independent bootstrap seed. */
  function executeForms(forms:Array<Form>):Array<Value> {
    var output:Array<Value> = [];
    for (form in forms) {
      var lowered:Array<Form> = switch (form) {
        case SumType(name, _, constructors): SumLowering.definitions(name, constructors);
        case RecordType(name, _, fields): RecordLowering.definitions(name, fields);
        case _: [form];
      };
      for (entry in lowered) switch (entry) {
        case Define(name, body):
          if (root.hasHere(name)) throw 'Already defined: ' + name;
          root.bind(name, evaluate(body, root));
        case Evaluate(body): output.push(evaluate(body, root));
        case _: throw 'Unlowered declaration';
      }
    }
    return output;
  }

  public function run(source:String, ?modules:String->Null<String>):Array<Value> {
    #if nail_seed_only
    // A bootstrap-only build cannot even use the host parser accidentally.
    throw 'Host source parser disabled in bootstrap-only build';
    #else
    steps = 0;
    return executeForms(new Parser(source).parse(modules));
    #end
  }

  /** Execute a first-class Syntax Program built by code running in Nail. */
  public function runSyntax(tree:Value):Array<Value> {
    steps = 0;
    return executeForms(SyntaxBridge.forms(MacroExpander.syntax(tree)));
  }

  /** Parse source with the tokenizer and Pratt parser written in Nail. */
  public function parseWithNail(source:String, ?modules:String->Null<String>):Value {
    steps = 0;
    var parse = root.lookup('parseSource');
    var resolve = modules == null ? null : (name:String) -> {
      var moduleSource = modules(name);
      if (moduleSource == null) return null;
      if (numeric.NumericDialect.isExact(moduleSource) != numeric.NumericDialect.isExact(source))
        throw 'Imported macro module uses incompatible numeric dialect: ' + name;
      return call(parse, Text(moduleSource));
    };
    var expanded = MacroExpander.syntax(call(parse, Text(source)), resolve);

    return numeric.LanguageVersion.isModern(source)
      ? call(root.lookup('modernRewrite'), expanded)
      : numeric.NumericDialect.isExact(source)
      ? call(root.lookup('exactRewrite'), expanded) : expanded;
  }

  /** Inspect the trusted standard record transformer before code generation.
      Call checkSyntax on the retained source, not on erased declarations. */
  public function expandRecordsWithNail(source:String, ?modules:String->Null<String>):Value {
    var tree = parseWithNail(source, modules);
    return call(root.lookup('expandRecordDeclarations'), tree);
  }

  /** Opt-in contract validation for the trusted Nail record transformer.
      The original nominal Program is checked before the expanded Program
      is returned; malformed/extra generated forms are rejected. */
  public function validatedRecordsWithNail(source:String, ?modules:String->Null<String>):Value
    return GeneratedDeclarationValidator.validate(expandRecordsWithNail(source, modules));

  /** Compile only after validating the transformer output against its source.
      This path is separate from the existing compileWithNail compatibility API. */
  public function compileValidatedWithNail(source:String, ?modules:String->Null<String>):Value
    return compileSyntaxWithNail(validatedRecordsWithNail(source, modules));

  /** Compile a generated Program only after checking explicit monomorphic
      signatures. Source declarations supply nominal types and existing
      definitions. Does not mutate the source checker or add VM instructions. */
  public function compileCheckedGenerated(source:Value, generated:Value,
      contracts:Array<{name:String, type:nail.NType}>):Value
    return compileSyntaxWithNail(
      GeneratedDeclarationValidator.validateTyped(source, generated, contracts));

  /** Use Nail's own parseSource function, then execute its output.
      The bootstrap Haxe parser is used only to load stdlib.nail. */
  public function runWithNail(source:String, ?modules:String->Null<String>):Array<Value> {
    var tree = parseWithNail(source, modules);
    return executeForms(SyntaxBridge.forms(MacroExpander.syntax(tree)));
  }

  public function runPlainWithNail(source:String, ?modules:String->Null<String>):Array<Dynamic>
    return plainResults(runWithNail(source, modules));

  /** Shared primitive environment for a bytecode executor; no source parsing. */
  public function bytecodeRoot():Env return root;

  /** Compile source using the compiler function written in Nail. */
  public function compileWithNail(source:String, ?modules:String->Null<String>):Value {
    if (modules != null) return compileSyntaxWithNail(parseWithNail(source, modules));
    steps = 0;

    var compiler = numeric.LanguageVersion.isModern(source) ? 'compileModernSource'
      : numeric.NumericDialect.isExact(source) ? 'compileExactSource' : 'compileSource';
    return call(root.lookup(compiler), Text(source));
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

  /** Development API delegates to the same renderer as ByteVm/BootRuntime. */
  public static function toPlain(value:Value):Dynamic return RuntimeValues.toPlain(value);

  /** Public convenience API, usable from the generated JS runtime. */
  public function runPlain(source:String, ?modules:String->Null<String>):Array<Dynamic>
    return RuntimeValues.plainResults(run(source, modules));

  public static function plainResults(values:Array<Value>):Array<Dynamic>
    return RuntimeValues.plainResults(values);
}
