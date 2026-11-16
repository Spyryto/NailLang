import haxe.Json;
import nail.NType;
import nail.TypeScheme;
import nail.Parser;
import nail.TypeChecker;
import nail.ModuleImage;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.BootstrapImage;
import nail.BootRuntime;
import nail.BytecodeCompiler;
import nail.ByteVm;
import nail.SyntaxEncoder;
import nail.SyntaxBridge;
import nail.Value;
import nail.Vm;

/** First closed structural row: order independent field identity,
    independent of nominal records and of source/runtime representation. */
class StructuralRecordsTestMain {
  static var passed = 0;
  static function ok(cond:Bool, label:String):Void {
    if (!cond) throw 'STRUCTURAL RECORDS: ' + label;
    passed++;
  }
  static function fails(f:Void->Void, needle:String):Void {
    var message = '';
    try f() catch (e:Dynamic) message = Std.string(e);
    ok(message.indexOf(needle) >= 0,
      'expected "' + needle + '" but got "' + message + '"');
  }

  static function same(source:String, expected:String):Void {
    var reference = BytecodeCompiler.compileSource(source);
    var host = new Vm(60000000);
    host.loadStdlib();
    var selfTree = host.parseWithNail(source);
    var compiledByNail = host.compileWithNail(source);
    ok(BootstrapImage.encode(reference) == BootstrapImage.encode(compiledByNail),
      'Haxe and Nail compiler produce identical structural bytecode');
    ok(BootstrapImage.encode(reference) ==
      BootstrapImage.encode(BytecodeCompiler.compile(SyntaxBridge.forms(selfTree))),
      'Nail parser AST bridge bytecode parity');
    ok(BootstrapImage.encode(reference) ==
      BootstrapImage.encode(BytecodeCompiler.compile(SyntaxBridge.forms(
        SyntaxEncoder.program(new Parser(source).parse())))),
      'structural Syntax roundtrip');
    ok(Json.stringify(new Vm(60000000).runPlain(source)) == expected,
      'AST interpreter structural records');
    ok(Json.stringify(new ByteVm(60000000).runPlain(reference)) == expected,
      'bytecode structural records');
    ok(Json.stringify(host.runPlainWithNail(source)) == expected,
      'Nail self parser structural records');
    ok(Json.stringify(new BootRuntime(60000000).runPlain(source)) == expected,
      'source-free compiler structural records');
  }

  public static function main():Void {
    var src = 'def left = { age = 36 , name = " Ada " } ; '
      + 'def right = { name = " Ada " , age = 36 } ; ';
    var checker = new TypeChecker();
    checker.check(src);
    ok(checker.signature('left') == '{age: Number, name: Text}',
      'closed structural rows canonicalized alphabetically');
    ok(checker.signature('right') == checker.signature('left'),
      'field ordering does not affect structural identity');
    ok(Json.stringify(checker.check('left == right ; right . age ;'))
      == '["Bool","Number"]', 'equality and projection of structural rows');
    ok(Json.stringify(checker.check('def identifier x = x ; identifier left ;'))
      == '["{age: Number, name: Text}"]',
      'structural type survives general polymorphic functions');

    same(src + 'left == right ; left . age ; right . name ;',
      '[true,36,"Ada"]');
    same('def flip x = { b = false , a = x } ; '
      + '( flip 9 ) . a ; ( flip true ) . b ;',
      '[9,false]');
    same('def inner = { score = 4 , good = true } ; '
      + 'def outer = { meta = inner , label = " blues " } ; '
      + 'outer . meta . score ;',
      '[4]');
    same('{ name = " A " , age = 1 } == { age = 1 , name = " A " } ;',
      '[true]');
    same('{ age = 3 , name = " A " } == { name = " A " , age = 4 } ;',
      '[false]');

    var nominal = 'type Person { age Number name Text } ; ';
    var nominalChecker = new TypeChecker();
    nominalChecker.check(nominal);
    fails(() -> nominalChecker.check('def mixed choose = if choose then '
        + 'Person { age = 1 , name = " X " } else { age = 1 , name = " X " } ;'),
      'cannot unify');
    fails(() -> new TypeChecker().check('if true then { x = 1 } else { y = 1 } ;'),
      'cannot unify');
    fails(() -> new TypeChecker().check('if true then { x = 1 } else { x = false } ;'),
      'cannot unify');
    fails(() -> new TypeChecker().check('{ x = 1 } . unknown ;'),
      'structural record has no field');
    fails(() -> new TypeChecker().check('{ callback = fun x -> x } == '
        + '{ callback = fun y -> y } ;'),
      'functions cannot be compared');
    fails(() -> new Parser('{ a = 1 , a = 2 } ;').parse(),
      'Duplicate named record field');
    fails(() -> new Parser('{ a = 1 , } ;').parse(), 'Trailing comma');
    fails(() -> new Parser('{ } ;').parse(), 'Named record requires at least one field');
    fails(() -> new TypeChecker().check('def get x = x . xyz ;'),
      'unknown record field');

    // The user order controls evaluation order (not canonical field order).
    fails(() -> new Vm().run('{ z = 1 / 0 , a = textAt " abc " 99 } ;'),
      'Division by zero');
    fails(() -> new Vm().run('{ a = textAt " abc " 99 , z = 1 / 0 } ;'),
      'Text index out of range');
    fails(() -> new BootRuntime().runPlain('{ z = 1 / 0 , a = textAt " abc " 99 } ;'),
      'Division by zero');
    fails(() -> new BootRuntime().runPlain('{ a = textAt " abc " 99 , z = 1 / 0 } ;'),
      'Text index out of range');
    var marker = 'UniqueStructuralMarker35';
    var encoded = BootstrapImage.encode(BytecodeCompiler.compileSource(
      '{ age = 7 , label = " ' + marker + ' " } ;'));
    ok(encoded.indexOf(marker) >= 0 &&
      encoded.indexOf(marker) == encoded.lastIndexOf(marker),
      'field expressions emitted only once');

    // Polymorphism and Eq constraints remain portable in a closed structural row.
    var maker = 'def make x = { value = x , ready = true } ;';
    var providerCheck = new TypeChecker();
    providerCheck.check(maker);
    ok(providerCheck.signature('make') == 'a -> {ready: Bool, value: a}',
      'structural polymorphic output scheme');
    var makerScheme = providerCheck.publicScheme('make');
    ok(makerScheme.quantified.length == 1,
      'quantification includes field type variables');
    // Independent consumers obtain a concrete structural row by applying
    // the imported polymorphic constructor before accessing its field.
    var core:PublicSourceModuleSpec = {
      name:'Profiles',source:maker,imports:[],exports:['make']
    };
    var use:PublicSourceModuleSpec = {
      name:'UseProfiles',
      source:'def extract n = ( importedMake n ) . value ; '
        + 'def isReady x = ( importedMake x ) . ready ;',
      imports:[{module:'Profiles',symbol:'make',alias:'importedMake',scheme:makerScheme}],
      exports:['extract','isReady']
    };
    var compiledCore = ModuleLinker.compilePublic(core);
    var compiledUse = ModuleLinker.compilePublic(use);
    var linked = ModuleLinker.linkImages([
      ModuleImage.encode(compiledUse),ModuleImage.encode(compiledCore)
    ]);
    ok(Vm.toPlain(linked.invoke('UseProfiles', 'extract', Number(116))) == 116,
      'structural record crosses separately compiled modules');
    ok(Vm.toPlain(linked.invoke('UseProfiles','isReady', Boolean(false))) == true,
      'polymorphic imported structural scheme instantiated at Bool');
    ok(linked.signature('UseProfiles','extract') == 'a -> a',
      'consumer retains polymorphism after field projection');
    var sameScheme:TypeScheme = {term:TFunction(TVariable(9),
      TStructural([
        {name:'ready',type:TBoolean},{name:'value',type:TVariable(9)}
      ])),quantified:[9],comparable:[]};
    var renamed = new TypeChecker();
    renamed.importPublicScheme('foreign', sameScheme);
    renamed.check('def use n = ( foreign n ) . value ;');
    ok(renamed.signature('use') == 'a -> a',
      'foreign quantified structural schemes are freshly rebound');
    fails(() -> TypeChecker.validatePublicScheme({
      term:TStructural([{name:'value',type:TNumber},{name:'ready',type:TBoolean}]),
      quantified:[],comparable:[]
    }), 'invalid structural record fields');
    fails(() -> TypeChecker.validatePublicScheme({
      term:TStructural([{name:'value',type:TVariable(12)}]),
      quantified:[],comparable:[]
    }), 'free type variable');
    var forged = ModuleLinker.compilePublic({
      name:'ForgedShape',
      source:'def read n = ( foreign n ) . value ;',
      imports:[{module:'Profiles',symbol:'make',alias:'foreign',
        scheme:{term:TFunction(TVariable(1),
          TStructural([{name:'value',type:TVariable(1)}])),
          quantified:[1],comparable:[]}}],
      exports:['read']
    });
    fails(() -> ModuleLinker.linkImages([
      ModuleImage.encode(compiledCore), ModuleImage.encode(forged)
    ]), 'import type mismatch');

    var example = haxe.Resource.getString('struct_practice');
    ok(example != null, 'practice example is bundled');
    same(example, '[116,20]');
    ok(Json.stringify(new TypeChecker().check(example)) ==
      '["Number","Number"]', 'practice example statically checks');

    trace('NailSeed v0.35 closed structural records: '+passed+' checks passed');
  }
}
