import haxe.Json;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.Parser;
import nail.TypeChecker;
import nail.Vm;

/** v0.46 choice B: explicit Add/Sub/Mul/Div relations. */
class ArithmeticRelationsTestMain {
  static var passed = 0;
  static function ok(value:Bool, title:String):Void {
    if (!value) throw 'ARITHMETIC RELATIONS: ' + title;
    passed++;
  }
  static function same(actual:Dynamic,expected:Dynamic,title:String):Void
    ok(Json.stringify(actual) == Json.stringify(expected),
      title + ' expected='+Json.stringify(expected)+' actual='+Json.stringify(actual));
  static function fails(action:Void->Void, message:String):Void {
    var actual='';
    try action() catch(e:Dynamic) actual=Std.string(e);
    ok(actual.indexOf(message)>=0,
      'expected "'+message+'" got "'+actual+'"');
  }
  public static function main():Void {
    var source='nail 0.46 ;\n'
      +'Add : Int Int Int ;\n'
      +'Add : Int Ratio Ratio ;\n'
      +'Add : Float Float Float ;\n'
      +'Sub : Int Int Int ;\n'
      +'Sub : Ratio Int Ratio ;\n'
      +'Sub : Float Float Float ;\n'
      +'Mul : Int Int Int ;\n'
      +'Mul : Ratio Ratio Ratio ;\n'
      +'Mul : Float Float Float ;\n'
      +'Div : Int Int Ratio ;\n'
      +'Div : Float Float Float ;\n'
      +'def add x y : Add = x + y ;\n'
      +'def sub x y : Sub = x - y ;\n'
      +'def mul x y : Mul = x * y ;\n'
      +'def divide x y : Div = x / y ;\n'
      +'add 20 22 ;\n'
      +'add 1 ( toRatio 2 ) ;\n'
      +'add 0.25 0.5 ;\n'
      +'sub 12 5 ;\n'
      +'sub ( 1 / 2 ) 1 ;\n'
      +'sub 8.0 0.5 ;\n'
      +'mul 6 7 ;\n'
      +'mul ( 1 / 3 ) ( 3 / 5 ) ;\n'
      +'mul 3.0 2.0 ;\n'
      +'divide 6 3 ;\n'
      +'divide 4.0 2.0 ;';
    var types=['Int','Ratio','Float','Int','Ratio','Float',
      'Int','Ratio','Float','Ratio','Float'];
    var expected:Array<Dynamic>=[
      'I:42/1','R:3/1',0.75,'I:7/1','R:-1/2',7.5,
      'I:42/1','R:1/5',6,'R:2/1',2
    ];
    var checker=new TypeChecker();
    same(checker.check(source),types,'statically constrained outcomes');
    for (name in ['add','sub','mul','divide']) {
      var label=switch (name) {
        case 'add':'Add';
        case 'sub':'Sub';
        case 'mul':'Mul';
        case _:'Div';
      };
      ok(checker.signature(name)==label+' a b c => a -> b -> c',
        name+' retains explicit type relation');
    }
    same(new Vm(40000000).runPlain(source), expected,'Haxe AST VM');
    var reference=BytecodeCompiler.compileSource(source);
    same(new ByteVm(40000000).runPlain(reference),expected,
      'reference structured bytecode');
    var boot=new BootRuntime(40000000);
    var rebuilt=boot.compile(source);
    ok(BootstrapImage.encode(reference)==BootstrapImage.encode(rebuilt),
      'Nail-written compiler parity (relation annotations erased)');
    same(boot.runBytecode(rebuilt).map(Vm.toPlain),expected,
      'source-free bootstrap runtime');
    var compatible='nail 0.45 ;\n'
      +'Div : Int Int Ratio ;\n'
      +'def divide x y : Div = x / y ; divide 2 3 ;';
    same(new TypeChecker().check(compatible),['Ratio'],
      '0.45 source is compatible with 0.46 type checker');
    same(new BootRuntime(40000000).runPlain(compatible),['R:2/3'],
      '0.46 VM accepts compatible v0.45 source');

    fails(() -> new TypeChecker().check(
      'nail 0.46 ; Add : Int Int Ratio ;'),
      'unsupported Add row');
    fails(() -> new TypeChecker().check(
      'nail 0.46 ; Add : Int Int Int ; Add : Int Int Int ;'),
      'duplicate Add input types');
    fails(() -> new TypeChecker().check(
      'nail 0.46 ; Add : Int Int Int ; '
      +'def add x y : Add = x + y ; add 1.0 2.0 ;'),
      'no Add instance');
    fails(() -> new TypeChecker().check(
      'nail 0.46 ; def add x y = x + y ;'),
      'no Add instance');
    fails(() -> new TypeChecker().check(
      'nail 0.46 ; def add x y : Add = x / y ;'),
      'cannot unify');
    fails(() -> new Parser(
      'nail 0.45 ; Add : Int Int Int ;').parseRaw(),
      'requires Nail 0.46');
    fails(() -> new Parser(
      'nail 0.45 ; def add x y : Add = x + y ;').parseRaw(),
      'requires Nail 0.46');
    fails(() -> new Parser(
      'nail 0.56 ; 1 ;').parseRaw(),
      'Unsupported Nail language version');
    fails(() -> new TypeChecker().check(
      'nail 0.46 ; 1 + 2.0 ;'),'explicit conversion');
    fails(() -> new Vm().run('nail 0.46 ; 1 + 2.0 ;'),
      'Mixed numeric domains');
    trace('NailLang 0.46 arithmetic relations: '+passed+' assertions passed');
  }
}
