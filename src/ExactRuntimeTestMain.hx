import haxe.Json;
import nail.Ast.Expr;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.ExactImage;
import nail.Parser;
import nail.TypeChecker;
import nail.Value;
import nail.Vm;
import numeric.FastNumber;

/** Complete opt-in numeric vertical slice: host, Nail-written compiler and
    source-free bootstrapped compiler must produce identical bytecode and
    execute exactly the same results. Old source is never upgraded. */
class ExactRuntimeTestMain {
  static var checks:Int = 0;

  static function ok(condition:Bool, name:String):Void {
    if (!condition) throw 'EXACT RUNTIME: ' + name;
    checks++;
  }

  static function expect(actual:Dynamic, value:Dynamic, name:String):Void {
    ok(Json.stringify(actual) == Json.stringify(value),
      name + ' expected ' + Json.stringify(value) +
      ' got ' + Json.stringify(actual));
  }

  static function fails(task:Void->Void, needle:String):Void {
    var message = '';
    try task() catch (e:Dynamic) message = Std.string(e);
    ok(message.indexOf(needle) >= 0,
      'expected error ' + needle + ' got ' + message);
  }

  static function runProgram(source:String, expected:Array<Dynamic>, vm:Vm,
      boot:BootRuntime):Void {
    var host = new Vm(20000000);
    expect(Vm.plainResults(host.run(source)), expected, 'host AST results');

    var reference = BytecodeCompiler.compileSource(source);
    var byteMachine = new ByteVm(20000000);
    expect(Vm.plainResults(byteMachine.run(reference)), expected,
      'Haxe bytecode compiler results');

    var selfCompiled = vm.compileWithNail(source);
    var actualImage = BootstrapImage.encode(selfCompiled);
    var referenceImage = BootstrapImage.encode(reference);
    ok(actualImage == referenceImage,
      'Nail compiler and reference produce identical bytecode for ' + source
      + '\\n self=' + actualImage.substr(0, 900)
      + '\\n ref=' + referenceImage.substr(0, 900));

    var selfMachine = new ByteVm(20000000);
    expect(Vm.plainResults(selfMachine.run(selfCompiled)), expected,
      'Nail-compiled bytecode results');

    var sourceFree = boot.compile(source);
    ok(BootstrapImage.encode(sourceFree) == BootstrapImage.encode(reference),
      'source-free compiler produces identical bytecode');
    expect(boot.runBytecode(sourceFree).map(Vm.toPlain), expected,
      'source-free exact execution');

    var wire = ExactImage.encode(reference);
    ok(wire.indexOf(ExactImage.FORMAT) >= 0
      && wire.indexOf('"sourceDialect":"0.29"') >= 0,
      'versioned exact image uses separate header');
    ok(BootstrapImage.encode(ExactImage.decode(wire))
      == BootstrapImage.encode(reference),
      'exact image is structurally lossless');
    fails(() -> BootstrapImage.decode(wire), 'format');
    var v2Machine = new ByteVm(20000000);
    expect(Vm.plainResults(v2Machine.run(ExactImage.decode(wire))), expected,
      'exact image executes without legacy reinterpretation');
  }

  public static function main():Void {
    var vm = new Vm(30000000);
    vm.loadStdlib();
    var boot = new BootRuntime(30000000);

    var exact = '# nail: 0.29\n';
    runProgram(exact + '0.1 + 0.2 ;', ['E:3/10'], vm, boot);
    runProgram(exact + '1 / 3 + 1 / 6 ;', ['E:1/2'], vm, boot);
    runProgram(exact + 'def twice x = x * 2 ; twice 17 ;',
      ['E:34/1'], vm, boot);
    runProgram(exact + 'def count n = if n == 0 then 0 else 1 + count ( n - 1 ) ; '
      + 'count 12 ;', ['E:12/1'], vm, boot);
    runProgram(exact + '999999999999999999999999999 / 3 ;',
      ['E:333333333333333333333333333/1'], vm, boot);

    runProgram(exact + 'type Person { age Number } ; ( Person 12 ) . age ;',
      ['E:12/1'], vm, boot);
    runProgram(exact + 'vectorGet ( vector [ 5 , 7 , 11 ] ) 1 ;',
      ['E:7/1'], vm, boot);
    runProgram(exact + 'vectorLength ( vector [ 5 , 7 , 11 ] ) ;',
      ['E:3/1'], vm, boot);
    runProgram(exact + 'textLength " hello " ;',
      ['E:5/1'], vm, boot);
    runProgram(exact + 'textAt " hello " 1 ;',
      ['e'], vm, boot);
    runProgram(exact + 'exactToFloat ( 1 / 2 ) ;',
      [0.5], vm, boot);
    runProgram(exact + 'exactFromText " 9.75 " ;',
      ['E:39/4'], vm, boot);
    runProgram(exact
      + 'macro double x = quote ( ( unquote x ) + ( unquote x ) ) ; '
      + 'expand double 0.1 ;', ['E:1/5'], vm, boot);

    // The old source dialect continues to behave as binary Float.
    var oldSource = '0.1 + 0.2 ;';
    var oldExpected:Float = 0.1 + 0.2;
    expect(new Vm().runPlain(oldSource), [oldExpected], 'legacy VM unchanged');
    expect(new ByteVm().runPlain(BytecodeCompiler.compileSource(oldSource)),
      [oldExpected], 'legacy reference compiler unchanged');
    expect(boot.runPlain(oldSource), [oldExpected],
      'legacy source-free compiler unchanged');

    var checker = new TypeChecker();
    expect(checker.preview(exact + '1 + 2 ;'), ['Exact'],
      'exact static type');
    expect(checker.preview('1 + 2 ;'), ['Number'], 'legacy numeric static type');
    expect(checker.preview(exact + 'def twice x = x * 2 ; twice 4 ;'),
      ['Exact'], 'exact inferred function body and call');
    expect(checker.preview(exact
      + 'type Person { age Number } ; ( Person 12 ) . age ;'),
      ['Exact'], 'nominal Number field means Exact in opted-in dialect');

    // The exact dialect rewrites indexing and length primitives too.
    expect(checker.preview(exact + 'vectorGet ( vector [ 5 , 7 ] ) 1 ;'),
      ['Exact'], 'exact vector index type');
    expect(checker.preview(exact + 'textLength " hello " ;'),
      ['Exact'], 'exact text length type');
    expect(checker.preview(exact + 'exactToFloat ( 1 / 2 ) ;'),
      ['Number'], 'explicit conversion to legacy Float type');
    // Exact is a numeric domain, not a dependent "integer" subtype:
    // fractional index rejection is necessarily checked at runtime.
    fails(() -> new Vm().run(exact + 'vectorGet ( vector [ 5 ] ) ( 1 / 2 ) ;'),
      'integer in range');
    // A macro module cannot silently change the meaning of Number.
    var moduleSource = (name:String) -> name == 'math'
      ? 'macro identity x = quote ( unquote x ) ; export identity ;'
      : null;
    var importing = exact + 'import identity from math ; expand identity 1 ;';
    fails(() -> BytecodeCompiler.compileSource(importing, moduleSource),
      'incompatible numeric dialect');
    fails(() -> vm.compileWithNail(importing, moduleSource),
      'incompatible numeric dialect');
    fails(() -> boot.compile(importing, moduleSource),
      'incompatible numeric dialect');
    fails(() -> numeric.NumericDialect.detect('# nail: 0.30\n1 ;'),
      'Unsupported Nail source dialect');
    fails(() -> new Vm().run(exact + '1 / 0 ;'), 'Division by zero');
    fails(() -> new ByteVm().run(BytecodeCompiler.compileSource(exact
      + '1 / 0 ;')), 'Division by zero');
    fails(() -> Vm.primitive('==', [
      ExactNumber(FastNumber.exact('1')), Number(1.0)
    ]), 'implicitly');

    // Exact-image validation protects the language-version boundary.
    var reference = BytecodeCompiler.compileSource(exact + '1 / 3 ;');
    var encoded = ExactImage.encode(reference);
    fails(() -> ExactImage.decode(StringTools.replace(encoded,
      'nailseed.postfix-image.v2-exact', 'nailseed.postfix-image.v1')),
      'format');
    fails(() -> ExactImage.decode(StringTools.replace(encoded,
      '"sourceDialect":"0.29"', '"sourceDialect":"0.27"')),
      'source dialect');
    // Modify the decoded JSON record: PHP escapes "/" inside JSON text,
    // so raw string replacement would depend on target-specific encoding.
    var corrupt:Dynamic = Json.parse(encoded);
    var rows:Array<Dynamic> = cast Reflect.field(corrupt, 'records');
    var changed = false;
    for (row in rows) {
      var cells:Array<Dynamic> = cast row;
      if (cells[0] == 'L' && cells[1] == 'ExactNumber' && !changed) {
        cells[2] = 'E:01/1';
        changed = true;
      }
    }
    ok(changed, 'exact image contained an exact numeric literal');
    fails(() -> ExactImage.decode(Json.stringify(corrupt)), 'Noncanonical');
    trace('NailSeed opt-in exact runtime: ' + checks + ' checks passed');
  }
}
