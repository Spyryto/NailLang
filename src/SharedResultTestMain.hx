import haxe.Json;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.ByteVm;
import nail.HostTextGrants;
import nail.ModuleImage;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.NType;
import nail.ResultValue;
import nail.TextReadCapability;
import nail.TypeChecker;
import nail.TypeScheme;
import nail.Value;
import nail.Vm;

/** Shared built-in CoreResult[a,e] with exhaustive matching across module images. */
class SharedResultTestMain {
  static var passed = 0;
  static function ok(cond:Bool, label:String):Void {
    if (!cond) throw 'SHARED RESULT: ' + label;
    passed++;
  }
  static function fails(fn:Void->Void, expected:String):Void {
    var actual = '';
    try fn() catch (e:Dynamic) actual = Std.string(e);
    ok(actual.indexOf(expected) >= 0,
      'expected "' + expected + '" but received "' + actual + '"');
  }
  static function reader(seen:Array<String>):TextReadCapability
    return new TextReadCapability(['song','empty','oversize','explodes'], key -> {
      seen.push(key);
      return switch (key) {
        case 'song': 'Swing 🪕';
        case 'empty': null;
        case 'oversize': '12345678901234567890';
        case 'explodes': throw 'private-token: /host/private';
        case _: null;
      };
    }, 15);
  static function source():String return
    'def load key = match readAsset key with '
    + '| CoreOk value -> value '
    + '| CoreErr why -> why ; '
    + 'load " song " ; load " denied " ; load " empty " ; '
    + 'load " oversize " ; load " explodes " ;';
  static function moduleSource():String return
    'def load key = readAsset key ;';
  static function consumerSource():String return
    'def explain key = match importedLoad key with '
    + '| CoreOk value -> value '
    + '| CoreErr why -> why ;';
  static function resultType():NType return
    TFunction(TText, TSum('CoreResult',[TText,TText]));
  static function resultScheme():TypeScheme return {
    term:resultType(), quantified:[], comparable:[]
  };
  static function moduleSpec(name:String):PublicSourceModuleSpec return {
    name:name, source:moduleSource(),
    imports:[{module:HostTextGrants.PROVIDER,
      symbol:HostTextGrants.READ_TEXT_RESULT, alias:'readAsset',
      scheme:resultScheme()}],
    exports:['load']
  };
  public static function main():Void {
    var checker = new TypeChecker();
    ok(checker.signature('CoreOk') == 'a -> CoreResult[a, b]',
      'CoreOk is polymorphic in successful and error payloads');
    ok(checker.signature('CoreErr') == 'a -> CoreResult[b, a]',
      'CoreErr is polymorphic in both type parameters');
    checker.check('def swapped r = match r with '
      + '| CoreOk ok -> CoreErr ok '
      + '| CoreErr error -> CoreOk error ;');
    ok(checker.signature('swapped').indexOf('CoreResult[') >= 0,
      'built-in pattern matching allows generic type transformations');
    fails(() -> new TypeChecker().check('def one r = match r with '
      + '| CoreOk v -> v ;'), 'non-exhaustive');
    fails(() -> new TypeChecker().check(
      'type CoreResult x = One x ;'), 'already defined CoreResult');
    fails(() -> new TypeChecker().check(
      'def unwrap r = match r with '
      + '| CoreOk v -> v | CoreErr reason -> reason ; '
      + 'unwrap 1 ;'), 'cannot unify');

    ok(new TypeChecker().signature('CoreOk').indexOf('CoreResult[') >= 0,
      'Result type is available without a source-level type definition');
    var hostChecker = new TypeChecker();
    hostChecker.importSignature('readAsset', TextReadCapability.resultSignature());
    hostChecker.check(source());
    ok(hostChecker.signature('load') == 'Text -> Text',
      'exhaustive pattern converts text Result to Text');
    var canonical = new TypeChecker();
    canonical.importSignature('readAsset', TextReadCapability.resultSignature());
    ok(canonical.signature('readAsset') == HostTextGrants.RESULT_SIGNATURE,
      'host ABI is the canonical HM type signature');
    fails(() -> new TypeChecker().check(source()), 'readAsset');

    var seenAst:Array<String> = [];
    var ast = new Vm(40000000);
    ast.grantTextResultReader('readAsset', reader(seenAst));
    var expected = ['Swing 🪕','denied','missing','too-large','backend-failure'];
    ok(Json.stringify(ast.runPlain(source())) == Json.stringify(expected),
      'AST handles both Result variants and sanitized errors');

    var seenByte:Array<String> = [];
    var byteVm = new ByteVm(40000000);
    byteVm.grantTextResultReader('readAsset', reader(seenByte));
    var code = BytecodeCompiler.compileSource(source());
    ok(Json.stringify(byteVm.runPlain(code)) == Json.stringify(expected),
      'bytecode runtime matches AST results');

    var seenBoot:Array<String> = [];
    var boot = new BootRuntime(40000000);
    boot.grantTextResultReader('readAsset', reader(seenBoot));
    ok(Json.stringify(boot.runPlain(source())) == Json.stringify(expected),
      'source-free compiler and runtime support Result pattern matching');
    ok(BootstrapImage.encode(code) == BootstrapImage.encode(boot.compile(source())),
      'reference and source-free compilers agree');
    ok(Json.stringify(seenAst) == Json.stringify(seenByte) &&
      Json.stringify(seenAst) == Json.stringify(seenBoot),
      'all three runtimes invoke only allowlisted host keys');

    var r = ResultValue.ok(Text('real'));
    var plain:Dynamic = Vm.toPlain(r);
    ok(Reflect.field(plain, "$type") == 'CoreResult' &&
      Reflect.field(plain, '#tag') == 'CoreOk',
      'result uses stable sum record envelope');
    ok(ResultValue.is(r, ResultValue.OK) && !ResultValue.is(r, ResultValue.ERR),
      'result tag discriminates variants');
    fails(() -> ResultValue.get(r, ResultValue.ERR), 'mismatched variant');
    fails(() -> ResultValue.tag(Text('fake')), 'Expected CoreResult');
    var corrupt = new haxe.ds.StringMap<Value>();
    corrupt.set('#tag', Text('CoreOk'));
    corrupt.set('#0', Text('x'));
    corrupt.set('extra', Text('attack'));
    fails(() -> ResultValue.tag(Record('CoreResult', corrupt)), 'Invalid CoreResult');
    fails(() -> new ByteVm().runPlain(code), 'readAsset');

    var songs = ModuleImage.encode(ModuleLinker.compilePublic(moduleSpec('Songs')));
    var songsImage = ModuleImage.decode(songs);
    ok(songsImage.exports[0].signature == HostTextGrants.RESULT_SIGNATURE,
      'portable module image exports CoreResult[Text,Text] with canonical identity');

    var consumer:PublicSourceModuleSpec = {
      name:'Consumer', source:consumerSource(),
      imports:[{module:'Songs',symbol:'load',alias:'importedLoad',
        scheme:resultScheme()}],
      exports:['explain']
    };
    var client = ModuleImage.encode(ModuleLinker.compilePublic(consumer));
    var grants = new HostTextGrants();
    var seenModules:Array<String> = [];
    grants.grantReadText('Songs', reader(seenModules));
    var linked = ModuleLinker.linkImages([client,songs], 40000000, grants);
    ok(Vm.toPlain(linked.invoke('Consumer','explain',Text('song'))) == 'Swing 🪕',
      'separately compiled consumer exhaustively matches producer Result');
    ok(Vm.toPlain(linked.invoke('Consumer','explain',Text('forbidden'))) == 'denied',
      'host result error remains typed across module boundary');
    ok(Json.stringify(seenModules) == '["song"]',
      'denied resource never reaches callback across module boundary');
    ok(linked.signature('Songs','load') == HostTextGrants.RESULT_SIGNATURE,
      'shared Result signature survives independent compilation and linking');
    fails(() -> ModuleLinker.linkImages([client,songs]), 'missing host grants');
    var wrong:PublicSourceModuleSpec = {
      name:'Wrong', source:'def use x = importedLoad x ;',
      imports:[{module:'Songs',symbol:'load',alias:'importedLoad',
        scheme:{term:TFunction(TText, TText),
          quantified:[], comparable:[]}}],
      exports:['use']
    };
    var badClient = ModuleImage.encode(ModuleLinker.compilePublic(wrong));
    fails(() -> ModuleLinker.linkImages([badClient,songs],40000000,grants),
      'import type mismatch');

    fails(() -> TypeChecker.validatePublicScheme({
      term:TSum('NotResult',[TText,TText]),
      quantified:[],comparable:[]
    }, true), 'algebraic public type identity');
    fails(() -> TypeChecker.validatePublicScheme({
      term:TSum('CoreResult',[TText]),
      quantified:[],comparable:[]
    }, true), 'algebraic public type identity');
    var maker = new TypeChecker();
    maker.check('def make x = CoreOk x ;');
    ok(maker.signature('make').indexOf('CoreResult[') >= 0,
      'Nail source can construct a Result without a type declaration');
    // Existing v0.32 programs declare a local type named Result.
    // The new standard name must not shadow it or change its identity.
    var oldResult = new TypeChecker();
    oldResult.check('type Result a e = Ok a | Err e ; '
      + 'def make x = Ok x ;');
    ok(oldResult.signature('make').indexOf('Result[') >= 0,
      'existing user-defined Result ADTs remain source-compatible');

    trace('NailSeed v0.38 shared Result: ' + passed + ' checks passed');
  }
}
