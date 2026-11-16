import haxe.Json;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.ModuleImage;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.Parser;
import nail.SyntaxBridge;
import nail.SyntaxEncoder;
import nail.TypeChecker;
import nail.Value;
import nail.Vm;

/** Named-field construction: static nominal checks, source-order evaluation
    and byte-for-byte parity of Haxe and Nail-written parsers/compilers. */
class NamedRecordsTestMain {
  static var passed = 0;
  static function ok(condition:Bool, description:String):Void {
    if (!condition) throw 'NAMED RECORDS: ' + description;
    passed++;
  }
  static function fails(f:Void->Void, contains:String):Void {
    var actual = '';
    try f() catch (e:Dynamic) actual = Std.string(e);
    ok(actual.indexOf(contains) >= 0,
      'expected ' + contains + ', got ' + actual);
  }
  static function same(source:String, expected:String):Void {
    var reference = BytecodeCompiler.compileSource(source);
    var host = new Vm(60000000);
    host.loadStdlib();
    var nailTree = host.parseWithNail(source);
    var self = host.compileWithNail(source);
    ok(BootstrapImage.encode(reference) == BootstrapImage.encode(self),
      'Nail/Haxe named-field bytecode parity');
    ok(BootstrapImage.encode(reference) ==
      BootstrapImage.encode(BytecodeCompiler.compile(SyntaxBridge.forms(nailTree))),
      'self parser emits identical lowered AST');
    ok(BootstrapImage.encode(reference) ==
      BootstrapImage.encode(BytecodeCompiler.compile(
        SyntaxBridge.forms(SyntaxEncoder.program(new Parser(source).parse())))),
      'Syntax bridge/encoder roundtrip');
    ok(Json.stringify(new Vm(60000000).runPlain(source)) == expected,
      'reference AST evaluator');
    ok(Json.stringify(new ByteVm(60000000).runPlain(reference)) == expected,
      'bytecode evaluator');
    ok(Json.stringify(host.runPlainWithNail(source)) == expected,
      'Nail parser + AST runtime');
    ok(Json.stringify(new BootRuntime(60000000).runPlain(source)) == expected,
      'source-free Nail compiler');
  }

  public static function main():Void {
    var person = 'type Person { name Text age Number } ; ';
    var box = 'type Box a { value a } ; ';
    var pair = 'type Pair a b { first a second b } ; ';

    same(person + '( Person { age = 36 , name = " Ada " } ) . name ;',
      '["Ada"]');
    same(person + '( Person { name = " Ada " , age = 36 } ) . age ;',
      '[36]');
    same(box + '( Box { value = true } ) . value ; '
      + '( Box { value = 7 } ) . value ;', '[true,7]');
    same(pair + '( Pair { second = true , first = 11 } ) . first ; '
      + '( Pair { first = " C " , second = 2 } ) . first ;',
      '[11,"C"]');
    var nested = person + 'type Badge { owner Person valid Bool } ; ';
    same(nested + '( Badge { valid = true , owner = Person { age = 8 , name = " Jo " } } )'
      + ' . owner . age ;', '[8]');

    var checker = new TypeChecker();
    checker.check(person + box + pair);
    ok(Json.stringify(checker.check('( Person { age = 21 , name = " X " } ) . age ;'))
      == '["Number"]', 'typed named-field reordering');
    ok(Json.stringify(checker.check('( Box { value = false } ) . value ;'))
      == '["Bool"]', 'generic record applied type');
    ok(Json.stringify(checker.check('( Pair { second = true , first = 13 } ) . first ;'))
      == '["Number"]', 'two independent field parameters');
    checker.check('def makeBox a = Box { value = a } ;');
    ok(checker.signature('makeBox') == 'a -> Box[a]',
      'polymorphic named constructor inferred');

    fails(() -> new Parser(person + 'Person { age = 23 , age = 42 } ;').parse(),
      'Duplicate named record field');
    fails(() -> new Parser(person + 'Person { age = 23 , name = " X " , } ;').parse(),
      'Trailing comma');
    fails(() -> new Parser(person + 'Person { } ;').parse(),
      'Named record requires at least one field');
    fails(() -> new TypeChecker().check(person +
      'Person { age = 23 , invalid = " X " } ;'), 'unknown named record field');
    fails(() -> new TypeChecker().check(person +
      'Person { age = 23 } ;'), 'missing named record field');
    fails(() -> new TypeChecker().check(person +
      'Person { age = " no " , name = " X " } ;'), 'cannot unify');

    // Error precedence proves the values execute in written order (not field
    // declaration order). The first failing expression determines the error.
    var firstError = person +
      'Person { age = 1 / 0 , name = textAt " abc " 99 } ;';
    var secondError = person +
      'Person { name = textAt " abc " 99 , age = 1 / 0 } ;';
    fails(() -> new Vm().run(firstError), 'Division by zero');
    fails(() -> new Vm().run(secondError), 'Text index out of range');
    fails(() -> new BootRuntime().runPlain(firstError), 'Division by zero');
    fails(() -> new BootRuntime().runPlain(secondError), 'Text index out of range');

    // The unique payload appears exactly once in emitted bytecode.
    var marker = 'UniqueLessonMarker34';
    var encoded = BootstrapImage.encode(BytecodeCompiler.compileSource(person
      + 'Person { age = 1 , name = " ' + marker + ' " } ;'));
    ok(encoded.indexOf(marker) >= 0 && encoded.indexOf(marker) == encoded.lastIndexOf(marker),
      'each named field expression emitted only once');

    var practice = haxe.Resource.getString('named_practice');
    ok(practice != null, 'practice example bundled');
    same(practice, '[116,20]');

    var core = 'type Lessons_Plan a { title Text value a } ; '
      + 'def create bpm = Lessons_Plan { value = bpm , title = " Picking " } ; '
      + 'def read plan = plan . value ;';
    var typecheck = new TypeChecker();
    typecheck.check(core);
    var makeContract = typecheck.publicScheme('create', true);
    var readContract = typecheck.publicScheme('read', true);
    var a:PublicSourceModuleSpec = {
      name:'Lessons', source:core, imports:[], exports:['create','read']
    };
    var b:PublicSourceModuleSpec = {
      name:'UseLessons',
      source:'def bpm x = imported_read ( imported_create x ) ;',
      imports:[
        {module:'Lessons',symbol:'create',alias:'imported_create',scheme:makeContract},
        {module:'Lessons',symbol:'read',alias:'imported_read',scheme:readContract}
      ], exports:['bpm']
    };
    var linked = ModuleLinker.linkImages([
      ModuleImage.encode(ModuleLinker.compilePublic(b)),
      ModuleImage.encode(ModuleLinker.compilePublic(a))
    ]);
    ok(Vm.toPlain(linked.invoke('UseLessons','bpm',Number(116))) == 116,
      'named generic record crosses two separately compiled modules');
    trace('NailSeed v0.34 named records: ' + passed + ' checks passed');
  }
}
