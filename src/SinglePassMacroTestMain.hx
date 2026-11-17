import haxe.Json;
import nail.Value;
import nail.Vm;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.BytecodeCompiler;

/** Regression for macro expansion before numeric rewrite and only once.
    Both Haxe's AST compiler and Nail's source-free compiler must agree.
    Exercises plain, Int/Ratio/Float, and Exact dialects with local and imported
    hygienic template macros. */
class SinglePassMacroTestMain {
  static var checks = 0;
  static function ok(good:Bool, title:String):Void {
    if (!good) throw 'SINGLE PASS MACROS: ' + title;
    checks++;
  }
  static function eq(a:Value, b:Value, title:String):Void {
    ok(BootstrapImage.encode(a) == BootstrapImage.encode(b), title);
  }
  static function output(source:String, ?modules:String->Null<String>):Array<Dynamic> {
    return new BootRuntime(40000000).runPlain(source, modules);
  }

  static function runCase(source:String, expected:Array<Dynamic>,
      ?modules:String->Null<String>):Void {
    var host = new Vm(40000000);
    host.loadStdlib();
    var boot = new BootRuntime(40000000);

    var reference = BytecodeCompiler.compileSource(source, modules);
    var self = host.compileWithNail(source, modules);
    var standalone = boot.compile(source, modules);
    eq(reference, self, 'host and Nail compiler bytecode parity: ' + source);
    eq(reference, standalone, 'source-free bytecode parity: ' + source);

    // Arbitrary Syntax passed to compileSyntax must still expand macros.
    // The internal entrypoint is only used once expansion has already run.
    var parsed = host.parseWithNail(source, modules);
    eq(reference, host.compileSyntaxWithNail(parsed),
      'public Syntax compiler still produces reference output: ' + source);
    eq(reference, boot.compileSyntax(parsed),
      'source-free Syntax compiler still produces reference output: ' + source);

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
      ? 'macro next x = quote ( unquote x + 1 ) ; export next ;' : null;
    runCase(
      'nail 0.49 ; import next from numbers ; expand next 41 ;',
      ['I:42/1'], resolver);

    var nested = (name:String) -> switch name {
      case 'outer': 'import next from inner ; macro twice x = quote '
        + '( expand next ( expand next ( unquote x ) ) ) ; export twice ;';
      case 'inner': 'macro next x = quote ( unquote x + 1 ) ; export next ;';
      case _: null;
    };
    runCase(
      'nail 0.49 ; import twice from outer ; expand twice 40 ;',
      ['I:42/1'], nested);

    fails(() -> new BootRuntime().run(
      'nail 0.49 ; macro broken x = quote ( unquote typo ) ;'),
      'unknown unquote parameter');
    fails(() -> new BootRuntime().run(
      'nail 0.49 ; expand absent 12 ;'), 'unknown macro absent');
    trace('Single-pass macro compiler: ' + checks + ' checks passed');
  }
}
