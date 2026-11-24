import haxe.Json;
import haxe.Timer;
import nail.Value;
import nail.Vm;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.TypeChecker;

/** Regression for macro expansion before numeric rewrite and only once.
    Both Haxe's AST compiler and Nail's source-free compiler must agree.
    Exercises plain, Int/Ratio/Float, and Exact dialects with local and imported
    hygienic template macros. */
class SinglePassMacroTestMain {
  static var checks = 0;
  // Observational timing only: do not change the production compiler or VM.
  static var bootInstances = 0;
  static var bootSeconds = 0.0;
  static var hostStdlibLoads = 0;
  static var hostStdlibSeconds = 0.0;
  static var referenceCompileSeconds = 0.0;
  static var hostNailCompileSeconds = 0.0;
  static var bootNailCompileSeconds = 0.0;
  // Comparison compilation is pure: reuse one loaded AST host across cases.
  // Negative probes and macro-spy tests retain separate VM instances.
  static var parityHost:Vm = null;
  static var parityCases = 0;

  static function comparisonHost():Vm {
    if (parityHost == null) {
      parityHost = new Vm(40000000);
      prepareHost(parityHost);
    }
    parityCases++;
    return parityHost;
  }

  static function freshBoot(?steps:Int):BootRuntime {
    var start = Timer.stamp();
    var runtime = steps == null ? new BootRuntime() : new BootRuntime(steps);
    bootSeconds += Timer.stamp() - start;
    bootInstances++;
    return runtime;
  }

  static function prepareHost(vm:Vm):Void {
    var start = Timer.stamp();
    vm.loadStdlib();
    hostStdlibSeconds += Timer.stamp() - start;
    hostStdlibLoads++;
  }

  static function profile(label:String, count:Int, seconds:Float):Void {
    trace('CI profile ' + label + ': count=' + count
      + ', total_ms=' + Math.round(seconds * 1000));
  }

  static function ok(good:Bool, title:String):Void {
    if (!good) throw 'SINGLE PASS MACROS: ' + title;
    checks++;
  }
  static function eq(a:Value, b:Value, title:String):Void {
    ok(BootstrapImage.encode(a) == BootstrapImage.encode(b), title);
  }
  static function output(source:String, ?modules:String->Null<String>):Array<Dynamic> {
    return freshBoot(40000000).runPlain(source, modules);
  }

  static function runCase(source:String, expected:Array<Dynamic>,
      ?modules:String->Null<String>):Void {
    var host = comparisonHost();
    var namesBefore = host.names().join("\n");
    var boot = freshBoot(40000000);

    var start = Timer.stamp();
    var reference = BytecodeCompiler.compileSource(source, modules);
    referenceCompileSeconds += Timer.stamp() - start;
    start = Timer.stamp();
    var self = host.compileWithNail(source, modules);
    hostNailCompileSeconds += Timer.stamp() - start;
    start = Timer.stamp();
    var standalone = boot.compile(source, modules);
    bootNailCompileSeconds += Timer.stamp() - start;
    eq(reference, self, 'host and Nail compiler bytecode parity: ' + source);
    eq(reference, standalone, 'source-free bytecode parity: ' + source);

    // Arbitrary Syntax passed to compileSyntax must still expand macros.
    // The internal entrypoint is only used once expansion has already run.
    var parsed = host.parseWithNail(source, modules);
    eq(reference, host.compileSyntaxWithNail(parsed),
      'public Syntax compiler still produces reference output: ' + source);
    eq(reference, boot.compileSyntax(parsed),
      'source-free Syntax compiler still produces reference output: ' + source);
    // Do not trade isolation for speed: compilation of any form must leave
    // global bindings unchanged before the next independent source is tested.
    ok(host.names().join("\n") == namesBefore,
      'source compilation must not mutate AST VM global names: ' + source);

    var actual = output(source, modules);
    ok(Json.stringify(actual) == Json.stringify(expected),
      'source-free evaluation expected ' + Json.stringify(expected)
      + ' got ' + Json.stringify(actual));
    checks++;
  }

  static function fails(action:Void->Void, needle:String):Void {
    var got = '';
    try action() catch (e:Dynamic) got = Std.string(e);
    ok(got.indexOf(needle) >= 0,
      'expected diagnostic ' + needle + ' got ' + got);
  }


  // Compilation of rejected source never mutates the global bindings.
  // Reuse bootstrapped runtimes across rejection probes to keep CI focused
  // on language diagnostics rather than repeated standard-library loading.
  static var rejectingVm:Vm = null;
  static var rejectingBoot:BootRuntime = null;
  static function rejectAll(source:String, modules:String->Null<String>,
      phrase:String):Void {
    if (rejectingVm == null) {
      rejectingVm = new Vm(40000000);
      prepareHost(rejectingVm);
      rejectingBoot = freshBoot(40000000);
    }
    fails(() -> BytecodeCompiler.compileSource(source, modules), phrase);
    fails(() -> new TypeChecker().check(source, modules), phrase);
    fails(() -> rejectingVm.compileWithNail(source, modules), phrase);
    fails(() -> rejectingBoot.compile(source, modules), phrase);
  }

  public static function main():Void {
    runCase(
      'macro lift x = quote ( unquote x + 1 ) ; expand lift 41 ;',
      [42]);
    runCase(
      'nail 0.49 ; macro lift x = quote ( unquote x + 1 ) ; expand lift 41 ;',
      ['I:42/1']);
    runCase(
      'nail 0.49 ; type Box { value Int } ; '
      + 'macro get x = quote ( ( unquote x ) . value ) ; '
      + 'expand get ( Box 42 ) ;',
      ['I:42/1']);
    runCase(
      'nail 0.49 ; def helper x = x + 1 ; '
      + 'macro bump x = quote ( helper ( unquote x ) ) ; '
      + 'let helper = false in expand bump 41 ;',
      ['I:42/1']);
    runCase(
      'nail 0.49 ; macro inc x = quote ( unquote x + 1 ) ; '
      + 'macro twice x = quote ( expand inc ( expand inc ( unquote x ) ) ) ; '
      + 'expand twice 40 ;',
      ['I:42/1']);
    runCase(
      '# nail: 0.29\nmacro half x = quote ( unquote x / 2 ) ; expand half 1 ;',
      ['E:1/2']);

    var resolver = (name:String) -> name == 'numbers'
      ? 'nail 0.49 ; macro next x = quote ( unquote x + 1 ) ; export next ;' : null;
    runCase(
      'nail 0.49 ; import next from numbers ; expand next 41 ;',
      ['I:42/1'], resolver);

    var nested = (name:String) -> switch name {
      case 'outer': 'nail 0.49 ; import next from inner ; macro twice x = quote '
        + '( expand next ( expand next ( unquote x ) ) ) ; export twice ;';
      case 'inner': 'nail 0.49 ; macro next x = quote ( unquote x + 1 ) ; export next ;';
      case _: null;
    };
    runCase(
      'nail 0.49 ; import twice from outer ; expand twice 40 ;',
      ['I:42/1'], nested);


    // Macro numeric literals are interpreted in the declaring module's
    // language dialect. Versionless modules may only enter versionless callers;
    // versioned modules must match the caller's exact Nail version.
    var bare = (name:String) -> name == 'numbers'
      ? 'macro next x = quote ( unquote x + 1 ) ; export next ;' : null;
    runCase('import next from numbers ; expand next 41 ;', [42], bare);
    var exact = (name:String) -> name == 'numbers'
      ? '# nail: 0.29\nmacro next x = quote ( unquote x + 1 ) ; export next ;'
      : null;
    runCase('# nail: 0.29\nimport next from numbers ; expand next 41 ;',
      ['E:42/1'], exact);

    rejectAll('nail 0.49 ; import next from numbers ; expand next 41 ;',
      bare, 'expected 0.49, got unversioned');
    var older = (name:String) -> name == 'numbers'
      ? 'nail 0.48 ; macro next x = quote ( unquote x + 1 ) ; export next ;' : null;
    rejectAll('nail 0.49 ; import next from numbers ; expand next 41 ;',
      older, 'expected 0.49, got 0.48');
    rejectAll('import next from numbers ; expand next 41 ;',
      resolver, 'expected unversioned, got 0.49');
    rejectAll('# nail: 0.29\nimport next from numbers ; expand next 41 ;',
      bare, 'incompatible numeric dialect');

    var wrongNested = (name:String) -> switch name {
      case 'outer': 'nail 0.49 ; import next from inner ; macro twice x = quote '
        + '( expand next ( expand next ( unquote x ) ) ) ; export twice ;';
      case 'inner': 'nail 0.48 ; macro next x = quote ( unquote x + 1 ) ; export next ;';
      case _: null;
    };
    rejectAll('nail 0.49 ; import twice from outer ; expand twice 40 ;',
      wrongNested, 'incompatible Nail version: inner');

    // Count invocations rather than merely comparing outputs: an unnecessary
    // second pass returns equal bytecode but still traverses the complete AST.
    var probe = new Vm(40000000);
    prepareHost(probe);
    var calls = 0;
    probe.bytecodeRoot().bind('macroExpandSyntax',
      HostFunction('single-pass-spy', tree -> {
        calls++;
        return nail.MacroExpander.syntax(tree);
      }));
    for (source in [
      'macro inc x = quote ( unquote x + 1 ) ; expand inc 41 ;',
      'nail 0.49 ; macro inc x = quote ( unquote x + 1 ) ; expand inc 41 ;',
      '# nail: 0.29\nmacro half x = quote ( unquote x / 2 ) ; expand half 1 ;'
    ]) {
      calls = 0;
      probe.compileWithNail(source);
      ok(calls == 1, 'one macro expansion per direct source compilation: '
        + source + ', observed ' + calls);
    }

    // The module resolver already expanded before invoking compiler code,
    // so the self-hosted code generator must not rescan imported macro Syntax.
    calls = 0;
    probe.compileWithNail('nail 0.49 ; import next from numbers ; expand next 41 ;',
      resolver);
    ok(calls == 0, 'module-resolved program must skip redundant expansion');

    // The public Syntax API remains responsible for expanding raw input.
    calls = 0;
    var raw = probe.invoke('parseSource',
      Text('nail 0.49 ; macro inc x = quote ( unquote x + 1 ) ; expand inc 41 ;'));
    probe.compileSyntaxWithNail(raw);
    ok(calls == 1, 'public compileSyntax expands raw Syntax exactly once');

    fails(() -> freshBoot().run(
      'nail 0.49 ; macro broken x = quote ( unquote typo ) ;'),
      'unknown unquote parameter');
    fails(() -> freshBoot().run(
      'nail 0.49 ; expand absent 12 ;'), 'unknown macro absent');
    profile('macro/BootRuntime init', bootInstances, bootSeconds);
    profile('macro/Vm stdlib load', hostStdlibLoads, hostStdlibSeconds);
    trace('CI profile macro/parity cases per reused host: ' + parityCases);
    profile('macro/Haxe reference compile', 1, referenceCompileSeconds);
    profile('macro/Vm Nail compile', 1, hostNailCompileSeconds);
    profile('macro/BootRuntime Nail compile', 1, bootNailCompileSeconds);
    // v0.59 experimental Nail-native local macro expansion entrypoint.
    // A matching Haxe-compiled bytecode is required before considering
    // replacement of the normal host macro-expansion primitive.
    var pureMacro='nail 0.55 ; macro inc x = quote ( unquote x + 1 ) ; '
      +'expand inc 41 ;';
    var nailMacroCode=freshBoot(40000000).invoke(
      'compileModernSourceNailMacros',Text(pureMacro));
    eq(BytecodeCompiler.compileSource(pureMacro),nailMacroCode,
      'Nail-written local macro expansion preserves independent compiler bytes');
    var pureSource='nail 0.55 ; def id x = x ; id 42 ;';
    eq(BytecodeCompiler.compileSource(pureSource),
      freshBoot(40000000).invoke(
        'compileModernSourceNailMacros',Text(pureSource)),
      'Nail-written no-macro expansion leaves ordinary source bytecode intact');

    trace('Single-pass macro compiler: ' + checks + ' checks passed');
  }
}
