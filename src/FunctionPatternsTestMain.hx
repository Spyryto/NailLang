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

/** F#-style unary function patterns lower to the same core as match. */
class FunctionPatternsTestMain {
  static var passed = 0;
  static function ok(value:Bool, description:String):Void {
    if (!value) throw 'FUNCTION PATTERNS: ' + description;
    passed++;
  }
  static function fails(f:Void->Void, needle:String):Void {
    var actual = '';
    try f() catch (e:Dynamic) actual = Std.string(e);
    ok(actual.indexOf(needle) >= 0, 'expected "' + needle + '" got "' + actual + '"');
  }
  static function same(source:String, expected:String):Void {
    var reference = BytecodeCompiler.compileSource(source);
    var self = new Vm(60000000);
    self.loadStdlib();
    var parsed = self.parseWithNail(source);
    var compiler = self.compileWithNail(source);
    ok(BootstrapImage.encode(reference) == BootstrapImage.encode(compiler),
      'Haxe and Nail compile function patterns identically');
    ok(BootstrapImage.encode(reference) ==
      BootstrapImage.encode(BytecodeCompiler.compile(SyntaxBridge.forms(parsed))),
      'Nail self-parser emits identical core');
    ok(BootstrapImage.encode(reference) ==
      BootstrapImage.encode(BytecodeCompiler.compile(
        SyntaxBridge.forms(SyntaxEncoder.program(new Parser(source).parse())))),
      'Haxe Syntax bridge/encoder roundtrip');
    ok(Json.stringify(new Vm(60000000).runPlain(source)) == expected,
      'AST runtime result');
    ok(Json.stringify(new ByteVm(60000000).runPlain(reference)) == expected,
      'bytecode runtime result');
    ok(Json.stringify(self.runPlainWithNail(source)) == expected,
      'Nail parser AST runtime result');
    ok(Json.stringify(new BootRuntime(60000000).runPlain(source)) == expected,
      'source-free bootstrap runtime result');
  }

  public static function main():Void {
    var first = 'def firstOr fallback = function '
      + '| [] -> fallback | head :: tail -> head ; ';
    same(first + 'firstOr 116 [] ; firstOr 116 [ 140 , 120 ] ;',
      '[116,140]');
    same('def nonempty = function | [] -> false | head :: tail -> true ; '
      + 'nonempty [] ; nonempty [ 12 ] ;', '[false,true]');
    same('def preferLast = function | head :: tail -> head | [] -> 0 ; '
      + 'preferLast [ 15 , 20 ] ; preferLast [] ;', '[15,0]');
    same('def nested = function | [] -> false | head :: tail -> '
      + '( function | [] -> true | next :: rest -> false ) tail ; '
      + 'nested [ 1 ] ; nested [ 1 , 2 ] ;', '[true,false]');
    var option = 'type Option a = None | Some a ; ';
    same(option + 'def isSome = function | None -> false | Some item -> true ; '
      + 'isSome None ; isSome ( Some 9 ) ;', '[false,true]');
    var status = 'type Status = Rest | Played Number ; ';
    same(status + 'def tempo = function | Rest -> 0 | Played bpm -> bpm ; '
      + 'tempo Rest ; tempo ( Played 116 ) ;', '[0,116]');
    same(status + 'def kind = function | Played bpm -> " played " | Rest -> " rest " ; '
      + 'kind ( Played 70 ) ; kind Rest ;', '["played","rest"]');

    var checker = new TypeChecker();
    checker.check(first);
    ok(checker.signature('firstOr') == 'a -> [a] -> a',
      'generalized list function pattern signature');
    checker.check('def apply fn arg = fn arg ;');
    ok(Json.stringify(checker.check('apply ( firstOr 0 ) [ 5 ] ;'))
      == '["Number"]', 'higher-order use is checked');
    checker.check(option + 'def isSome = function '
      + '| None -> false | Some item -> true ;');
    ok(checker.signature('isSome') == 'Option[a] -> Bool',
      'ADT function patterns infer nominal generic type');
    ok(Json.stringify(checker.check('isSome ( Some true ) ;')) == '["Bool"]',
      'ADT function pattern instantiates generic input');
    fails(() -> new Parser('function | [] -> 0 ;').parse(), 'Expected |');
    fails(() -> new Parser('function | [] -> 0 | [] -> 1 ;').parse(),
      'Duplicate empty-list pattern');
    fails(() -> new Parser('function | [] -> 0 | item :: item -> 1 ;').parse(),
      'Duplicate list pattern binding');
    fails(() -> new Parser('def function = 1 ;').parse(), 'Expected');
    fails(() -> new TypeChecker().check(option
      + 'def partial = function | Some value -> true ;'),
      'non-exhaustive match');
    fails(() -> new TypeChecker().check(
      'type First = One ; type Second = Two ; '
      + 'def mixed = function | One -> 1 | Two -> 2 ;'),
      'mixed constructors');

    var example = haxe.Resource.getString('function_example');
    ok(example != null, 'guitar practice example included');
    same(example, '[116,0]');

    var provider = 'def hasAny = function | [] -> false | head :: tail -> true ;';
    var tc = new TypeChecker();
    tc.check(provider);
    var scheme = tc.publicScheme('hasAny');
    var a:PublicSourceModuleSpec = {
      name:'ListUtils', source:provider, imports:[], exports:['hasAny']
    };
    var b:PublicSourceModuleSpec = {
      name:'UseList',
      source:'def hasScores xs = foreign_hasAny xs ;',
      imports:[{module:'ListUtils',symbol:'hasAny',
        alias:'foreign_hasAny',scheme:scheme}],
      exports:['hasScores']
    };
    var linked = ModuleLinker.linkImages([
      ModuleImage.encode(ModuleLinker.compilePublic(b)),
      ModuleImage.encode(ModuleLinker.compilePublic(a))
    ]);
    ok(Vm.toPlain(linked.invoke('UseList','hasScores',Cons(Number(116),Nil))) == true,
      'function-pattern export links across compiled module boundaries');
    ok(Vm.toPlain(linked.invoke('UseList','hasScores',Nil)) == false,
      'linked function handles second exhaustive branch');
    trace('NailSeed v0.36 F# pattern function expressions: '+passed+' checks passed');
  }
}
