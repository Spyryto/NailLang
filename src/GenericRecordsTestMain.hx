import haxe.Json;
import nail.Parser;
import nail.TypeChecker;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.ModuleImage;
import nail.BytecodeCompiler;
import nail.BootstrapImage;
import nail.BootRuntime;
import nail.SyntaxBridge;
import nail.SyntaxEncoder;
import nail.Value;
import nail.Vm;

/** Generic nominal records: no new expression nodes or bytecode opcodes. */
class GenericRecordsTestMain {
  static var passed = 0;
  static function ok(value:Bool, label:String):Void {
    if (!value) throw 'GENERIC RECORDS: ' + label;
    passed++;
  }
  static function fails(f:Void->Void, needle:String):Void {
    var message = '';
    try f() catch (e:Dynamic) message = Std.string(e);
    ok(message.indexOf(needle) >= 0,
      'expected "' + needle + '", got "' + message + '"');
  }
  static function sameSource(source:String, result:String):Void {
    var host = new Vm(40000000);
    host.loadStdlib();
    var reference = BytecodeCompiler.compileSource(source);
    var parsed = host.parseWithNail(source);
    var viaNail = host.compileWithNail(source);
    ok(BootstrapImage.encode(reference) == BootstrapImage.encode(viaNail),
      'Haxe and Nail compiler bytecode parity');
    ok(BootstrapImage.encode(reference) ==
      BootstrapImage.encode(BytecodeCompiler.compile(SyntaxBridge.forms(parsed))),
      'self-parser Syntax bridge');
    ok(BootstrapImage.encode(reference) ==
      BootstrapImage.encode(BytecodeCompiler.compile(SyntaxBridge.forms(
        SyntaxEncoder.program(new Parser(source).parse())))),
      'Haxe Syntax roundtrip');
    ok(Json.stringify(host.runPlainWithNail(source)) == result,
      'Nail-written parser and AST execution');
    ok(Json.stringify(new BootRuntime(40000000).runPlain(source)) == result,
      'source-free bootstrap execution');
    ok(Json.stringify(new Vm(40000000).runPlain(source)) == result,
      'reference runtime execution');
    ok(Json.stringify(new nail.ByteVm(40000000).runPlain(reference)) == result,
      'bytecode runtime execution');
  }

  public static function main():Void {
    var checker = new TypeChecker();
    checker.check('type Box a { value a } ; type Pair a b { first a second b } ;');
    ok(checker.signature('Box') == 'a -> Box[a]', 'generic Box constructor');
    ok(checker.signature('Box.value') == 'Box[a] -> a', 'generic Box accessor');
    ok(checker.signature('Pair') == 'a -> b -> Pair[a, b]', 'two-parameter constructor');
    ok(checker.signature('Pair.first') == 'Pair[a, b] -> a', 'first projection');
    ok(checker.signature('Pair.second') == 'Pair[a, b] -> b', 'second projection');
    checker.check('def wrap x = Box x ; def unwrap x = x . value ;');
    ok(checker.signature('wrap') == 'a -> Box[a]', 'polymorphic wrap inferred');
    ok(checker.signature('unwrap') == 'Box[a] -> a', 'dot projection propagates type argument');
    ok(Json.stringify(checker.check('( Box true ) . value ; ( Pair 8 false ) . second ;')) ==
      '["Bool","Bool"]', 'instantiation works at independent concrete types');

    var box = 'type Box a { value a } ; ';
    var pair = 'type Pair a b { first a second b } ; ';
    sameSource(box + 'def get x = ( Box x ) . value ; get 7 ; get true ;',
      '[7,true]');
    sameSource(pair + '( Pair 23 true ) . first ; ( Pair 9 false ) . second ;',
      '[23,false]');
    sameSource(box + 'Box " Ada " == Box " Ada " ;', '[true]');

    fails(() -> new TypeChecker().check(box + 'Box 1 == Box ( fun x -> x ) ;'),
      'cannot unify');
    fails(() -> new TypeChecker().check(box + 'Box ( fun x -> x ) == Box ( fun y -> y ) ;'),
      'functions cannot be compared');
    fails(() -> new TypeChecker().check(
      'type Twin a { left a right a } ; Twin 1 true ;'), 'cannot unify');
    fails(() -> new TypeChecker().check(box +
      'type Holder { inner Box } ;'), 'parameterized record field type requires explicit application');
    fails(() -> new Parser('type Box a a { value a } ;').parse(),
      'Invalid or duplicate record type parameter');
    fails(() -> new TypeChecker().check(box +
      'type Label { value Text } ; def ambiguous x = x . value ;'),
      'ambiguous record field');

    var storeSource = 'type Store_Box a { value a } ; '
      + 'def make x = Store_Box x ; def get p = p . value ;';
    var storeCheck = new TypeChecker();
    storeCheck.check(storeSource);
    var makeScheme = storeCheck.publicScheme('make', true);
    var getScheme = storeCheck.publicScheme('get', true);
    ok(storeCheck.signature('make') == 'a -> Store_Box[a]',
      'provider-qualified generic public constructor');
    ok(storeCheck.signature('get') == 'Store_Box[a] -> a',
      'provider-qualified generic public accessor');
    fails(() -> storeCheck.publicScheme('make'), 'nominal types require public type identity');
    var store:PublicSourceModuleSpec = {
      name:'Store',source:storeSource,imports:[],exports:['make','get']
    };
    var useStore:PublicSourceModuleSpec = {
      name:'UseStore',
      source:'def run n = if foreign_get ( foreign_make true ) '
        + 'then foreign_get ( foreign_make n ) + 1 else 0 ;',
      imports:[
        {module:'Store',symbol:'make',alias:'foreign_make',scheme:makeScheme},
        {module:'Store',symbol:'get',alias:'foreign_get',scheme:getScheme}
      ],
      exports:['run']
    };
    var compiledStore = ModuleLinker.compilePublic(store);
    var compiledClient = ModuleLinker.compilePublic(useStore);
    ok(compiledStore.exports[0].signature == 'a -> Store_Box[a]',
      'generic public ABI is canonical');
    var linked = ModuleLinker.linkImages([
      ModuleImage.encode(compiledClient),ModuleImage.encode(compiledStore)
    ]);
    ok(Vm.toPlain(linked.invoke('UseStore','run',Number(41))) == 42,
      'generic record crosses independently compiled modules');
    ok(linked.signature('UseStore','run') == 'Number -> Number',
      'client instantiates imported generic methods at two types');
    var otherSource = 'type Other_Box a { value a } ; def get p = p . value ;';
    var otherCheck = new TypeChecker();
    otherCheck.check(otherSource);
    var otherGet = otherCheck.publicScheme('get', true);
    fails(() -> ModuleLinker.compilePublic({
      name:'Mixed',source:'def wrong n = foreign_get ( foreign_make n ) ;',
      imports:[
        {module:'Store',symbol:'make',alias:'foreign_make',scheme:makeScheme},
        {module:'Other',symbol:'get',alias:'foreign_get',scheme:otherGet}
      ],exports:['wrong']
    }), 'cannot unify');
    fails(() -> ModuleLinker.compilePublic({
      name:'Forged',source:'def wrong x = wrong_make x ;',
      imports:[{module:'Other',symbol:'make',alias:'wrong_make',scheme:makeScheme}],
      exports:['wrong']
    }), 'imported nominal owner mismatch');
    trace('NailSeed v0.33 generic nominal records: ' + passed + ' checks passed');
  }
}
