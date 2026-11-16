import haxe.Json;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.TextReadCapability;
import nail.TypeChecker;
import nail.Vm;

/** Explicit host-read capabilities: same Nail program on all three backends. */
class HostCapabilitiesTestMain {
  static var passed:Int = 0;

  static function ok(cond:Bool, label:String):Void {
    if (!cond) throw 'HOST CAPABILITIES: ' + label;
    passed++;
  }

  static function fails(f:Void->Void, needle:String):Void {
    var message = '';
    try f() catch (e:Dynamic) message = Std.string(e);
    ok(message.indexOf(needle) >= 0,
      'expected "' + needle + '"; got "' + message + '"');
  }

  static function reader(seen:Array<String>):TextReadCapability {
    return new TextReadCapability(['song', 'missing', 'large', 'boom'], key -> {
      seen.push(key);
      return switch (key) {
        case 'song': 'Jazz 🪕';
        case 'large': '123456789012345';
        case 'boom': throw 'Secret backend error: /private/config';
        case _: null;
      };
    }, 12);
  }

  static function program():String return
    'def show key = let result = readAsset key in '
    + 'if result . ok then result . value else result . error ; '
    + 'show " song " ; '
    + 'show " ignored " ; '
    + 'show " missing " ; '
    + 'show " large " ; '
    + 'show " boom " ;';

  static function resultExpected():String return
    Json.stringify(Json.parse('["Jazz 🪕","denied","missing","too-large","backend-failure"]'));

  public static function main():Void {
    var source = program();
    var checker = new TypeChecker();
    checker.importSignature('readAsset', TextReadCapability.signature());
    ok(Json.stringify(checker.check(source)) ==
      '["Text","Text","Text","Text","Text"]',
      'imported host capability has statically checked result shape');
    ok(checker.signature('show') == 'Text -> Text',
      'derived function has a closed Text -> Text signature');
    fails(() -> new TypeChecker().check(source), 'readAsset');
    var wrong = new TypeChecker();
    wrong.importSignature('readAsset', TextReadCapability.signature());
    fails(() -> wrong.check('readAsset 123 ;'), 'cannot unify');

    var hostReads:Array<String> = [];
    var ast = new Vm(40000000);
    ast.grantTextReader('readAsset', reader(hostReads));
    ok(Json.stringify(ast.runPlain(source)) == resultExpected(),
      'AST VM checks allowlist and returns recoverable outcomes');
    ok(Json.stringify(hostReads) == '["song","missing","large","boom"]',
      'denied request never reaches host callback');

    var byteReads:Array<String> = [];
    var byteVm = new ByteVm(40000000);
    byteVm.grantTextReader('readAsset', reader(byteReads));
    var program = BytecodeCompiler.compileSource(source);
    ok(Json.stringify(byteVm.runPlain(program)) == resultExpected(),
      'bytecode VM has the same capability behavior');
    ok(Json.stringify(byteReads) == Json.stringify(hostReads),
      'AST and bytecode invoke the same allowed resources');

    var bootReads:Array<String> = [];
    var boot = new BootRuntime(40000000);
    boot.grantTextReader('readAsset', reader(bootReads));
    ok(Json.stringify(boot.runPlain(source)) == resultExpected(),
      'source-free compiler and VM respect host grants');
    ok(Json.stringify(bootReads) == Json.stringify(hostReads),
      'bootstrapped runtime has equivalent resource isolation');
    ok(BootstrapImage.encode(program) ==
      BootstrapImage.encode(boot.compile(source)),
      'source-free and Haxe compilers emit identical bytecode');

    fails(() -> new Vm().runPlain(source), 'Unknown name: readAsset');
    fails(() -> new ByteVm().runPlain(program), 'Unknown name: readAsset');
    fails(() -> new BootRuntime().runPlain(source), 'Unknown name: readAsset');
    fails(() -> ast.grantTextReader('readAsset', reader([])), 'Duplicate');
    fails(() -> new Vm().grantTextReader('textAt', reader([])), 'Duplicate');
    fails(() -> new Vm().grantTextReader('not-valid!', reader([])), 'Invalid');
    fails(() -> new TextReadCapability(['ok', 'ok'], name -> null), 'duplicate');
    fails(() -> new TextReadCapability(['../private'], name -> null), 'resource name');
    fails(() -> new TextReadCapability(['safe'], name -> null, 0), 'configuration');
    fails(() -> Vm.toPlain(reader([]).asValue()), 'Cannot serialize function');

    var throws = new TextReadCapability(['allowed'], key -> {
      throw 'internal backend trace';
      return null;
    });
    var failed = Vm.toPlain(throws.read(nail.Value.Text('allowed')));
    ok(Reflect.field(failed, 'error') == 'backend-failure',
      'backend details are not exposed to source');

    trace('NailSeed v0.38 read capabilities: ' + passed + ' checks passed');
  }
}
