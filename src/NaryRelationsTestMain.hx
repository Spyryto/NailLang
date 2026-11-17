import haxe.Json;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.Parser;
import nail.TypeChecker;
import nail.TypeRelation;
import nail.Vm;
import numeric.LanguageVersion;

class NaryRelationsTestMain {
  static var count = 0;
  static function ok(pass:Bool,label:String):Void {
    if (!pass) throw 'NARY RELATIONS: '+label;
    count++;
  }
  static function eq(actual:Dynamic, expected:Dynamic, label:String):Void {
    ok(Json.stringify(actual)==Json.stringify(expected),
      label+' got '+Json.stringify(actual)+' expected '+Json.stringify(expected));
  }
  static function fails(task:Void->Void,needle:String):Void {
    var error='';
    try task() catch (e:Dynamic) error=Std.string(e);
    ok(error.indexOf(needle)>=0,
      'expected "'+needle+'" but got "'+error+'"');
  }
  public static function main():Void {
    var source='nail 0.49 ;\n'
      +'Square : Int Int ;\n'
      +'Square : Ratio Ratio ;\n'
      +'Square : Float Float ;\n'
      +'Blend : Int Int Int Int ;\n'
      +'Blend : Float Float Float Float ;\n'
      +'Echo : Text Text ;\n'
      +'Echo : Bool Bool ;\n'
      +'Choose : Text Bool Text ;\n'
      +'type Person { name Text age Int } ;\n'
      +'PersonName : Person Text ;\n'
      +'def square x : Square = x * x ;\n'
      +'def blend a b c : Blend = a * b + c ;\n'
      +'def echo x : Echo = x ;\n'
      +'def choose x flag : Choose = if flag then x else x ;\n'
      +'def personName p : PersonName = p . name ;\n'
      +'square 4 ;\n'
      +'square ( 1 / 2 ) ;\n'
      +'square 1.5 ;\n'
      +'blend 2 3 4 ;\n'
      +'blend 2.0 3.0 4.0 ;\n'
      +'echo " ciao " ;\n'
      +'echo true ;\n'
      +'choose " a " true ;\n'
      +'personName ( Person " Alice " 42 ) ;';
    var types=['Int','Ratio','Float','Int','Float','Text','Bool','Text','Text'];
    var expected:Array<Dynamic>=['I:16/1','R:1/4',2.25,'I:10/1',10.0,
      'ciao',true,'a','Alice'];
    var checker=new TypeChecker();
    eq(checker.check(source),types,'static n-ary checking');
    ok(checker.signature('square')=='Square a b => a -> b',
      'unary constrained signature');
    ok(checker.signature('blend')=='Blend a b c d => a -> b -> c -> d',
      'ternary constrained signature');
    ok(checker.signature('echo')=='Echo a b => a -> b',
      'non-numeric relation signature');
    var c=checker.publicRelation('square');
    ok(c.rows.length==3 && TypeRelation.arity(c)==1,
      'public unary relation includes all concrete cases');
    var reference=BytecodeCompiler.compileSource(source);
    eq(new Vm(40000000).runPlain(source),expected,'host AST runtime');
    eq(new ByteVm(40000000).runPlain(reference),expected,'reference bytecode');
    var boot=new BootRuntime(40000000);
    var self=boot.compile(source);
    ok(BootstrapImage.encode(self)==BootstrapImage.encode(reference),
      'Nail-written generic relation parser erases rows, preserves bytecode');
    eq(boot.runBytecode(self).map(Vm.toPlain),expected,'source-free runtime');

    fails(() -> new TypeChecker().check(
      'nail 0.49 ; Square : Int Int ; Square : Int Float ;'),
      'duplicate input types');
    fails(() -> new TypeChecker().check(
      'nail 0.49 ; F : Int Int ; F : Int Int Int ;'),
      'inconsistent arity');
    fails(() -> new TypeChecker().check(
      'nail 0.49 ; Square : Int Int ; def square x y : Square = x ;'),
      'definition arity');
    fails(() -> new TypeChecker().check(
      'nail 0.49 ; Square : Int Int ; def square x : Square = x / x ;'),
      'cannot unify');
    fails(() -> new TypeChecker().check(
      'nail 0.49 ; Square : Int Int ; def square x : Square = x * x ; square 2.0 ;'),
      'no Square instance');
    fails(() -> new TypeChecker().check(
      'nail 0.49 ; Square : Int Int ; def square x : Square = x * x ; square ;'),
      'requires 1');
    fails(() -> new TypeChecker().check(
      'nail 0.49 ; Blend : Int Int Int Int ; def blend x y z : Blend = x + y + z ; '
      +'blend 1 2 ;'),'requires 3');
    fails(() -> new TypeChecker().check(
      'nail 0.49 ; Blend : Int Int Int Int ; def blend x y z : Blend = x + y + z ; '
      +'blend 1 2 3 4 ;'),'requires 3');
    fails(() -> new TypeChecker().check(
      'nail 0.49 ; def f x : Undefined = x ;'),
      'missing declaration');
    fails(() -> new TypeChecker().check(
      'nail 0.49 ; Echo : Text Text ; def echo x : Echo = x ; '
      +'def wrapper x = echo x ;'), 'no Echo instance');
    fails(() -> new Parser(
      'nail 0.48 ; Square : Int Int ;').parseRaw(),
      'Expected');
    fails(() -> new Parser(
      'nail 0.51 ; 1 ;').parseRaw(),
      'Unsupported Nail language version');

    // Source without new semantics remains fully compatible.
    eq(new TypeChecker().check('nail 0.48 ; 2 / 3 ;'),['Ratio'],
      'v0.48 numeric source remains compatible');
    // Upper boundary: sixteen input parameters and one result type.
    var sixteen=[for (i in 0...17) 'Int'].join(' ');
    var parameters=[for (i in 1...17) 'p'+i].join(' ');
    var arguments=[for (i in 1...17) Std.string(i)].join(' ');
    var maxArity='nail 0.49 ; Many : '+sixteen+' ; '
      +'def first '+parameters+' : Many = p1 ; first '+arguments+' ;';
    eq(new TypeChecker().check(maxArity),['Int'],
      'maximum supported arity is 16');
    eq(new Vm().runPlain(maxArity),['I:1/1'],
      'sixteen-argument function executes');
    var maxReference=BytecodeCompiler.compileSource(maxArity);
    ok(BootstrapImage.encode(new BootRuntime(40000000).compile(maxArity))
      ==BootstrapImage.encode(maxReference),
      'sixteen-argument function self-hosts to identical bytecode');
    fails(() -> TypeRelation.parseRow(['Int']),
      'expected 1 to 16 parameter types');
    fails(() -> TypeRelation.parseRow([for (i in 0...18) 'Int']),
      'expected 1 to 16 parameter types');
    trace('Nail v0.49 n-ary relation checks passed: '+count);
  }
}
