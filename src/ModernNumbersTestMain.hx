import haxe.Json;
import nail.Vm;
import nail.ByteVm;
import nail.BootRuntime;
import nail.BytecodeCompiler;
import nail.BootstrapImage;
import nail.TypeChecker;
import nail.Parser;
import numeric.LanguageVersion;

class ModernNumbersTestMain {
  static var checks = 0;
  static function ok(c:Bool,n:String):Void {
    if (!c) throw 'MODERN NUMBERS: ' + n;
    checks++;
  }
  static function eq(actual:Dynamic, expected:Dynamic, n:String):Void {
    ok(Json.stringify(actual) == Json.stringify(expected),
      n + ': ' + Json.stringify(actual) + ' != ' + Json.stringify(expected));
  }
  static function fails(f:Void->Void, msg:String):Void {
    var got='';
    try f() catch (e:Dynamic) got=Std.string(e);
    ok(got.indexOf(msg)>=0,'expected "'+msg+'" but got "'+got+'"');
  }

  public static function main():Void {
    var header='nail 0.45 ;\n';
    var table=
      'Div : Int Int Ratio ;\n'
      + 'Div : Ratio Ratio Ratio ;\n'
      + 'Div : Float Float Float ;\n'
      + 'Div : Int Ratio Ratio ;\n'
      + 'Div : Ratio Int Ratio ;\n';
    var source=header + table
      + 'def divide x y : Div = x / y ;\n'
      + 'divide 9 2 ;\n'
      + 'divide 9.0 2.0 ;\n'
      + 'divide ( toRatio 9 ) 2 ;\n'
      + 'divide 9 ( toRatio 2 ) ;\n'
      + 'divide ( toRatio 9 ) ( toRatio 2 ) ;\n'
      + '4 + 3 ;\n'
      + '4 + ( toRatio 1 ) ;\n'
      + '0.1 + 0.2 ;\n'
      + 'toFloat ( 1 / 2 ) ;\n'
      + 'ratioFromText " 0.1 " + ratioFromText " 0.2 " ;\n'
      + 'intFromText " 999999999999999999999999999999 " + 1 ;\n'
      + '1 / 3 + 1 / 6 ;\n'
      + 'textLength " hello " ;\n'
      + 'textAt " hello " 1 ;\n'
      + 'vectorGet ( vector [ 3 , 5 ] ) 1 ;\n'
      + 'vectorLength ( vector [ 3 , 5 ] ) ;';
    var expected:Array<Dynamic>=[
      'R:9/2',4.5,'R:9/2','R:9/2','R:9/2',
      'I:7/1','R:5/1',0.1+0.2,0.5,'R:3/10',
      'I:1000000000000000000000000000000/1','R:1/2',
      'I:5/1','e','I:5/1','I:2/1'
    ];
    var types:Array<String>=[
      'Ratio','Float','Ratio','Ratio','Ratio',
      'Int','Ratio','Float','Float','Ratio','Int','Ratio',
      'Int','Text','Int','Int'
    ];
    ok(LanguageVersion.isModern(source),'explicit source header chooses modern semantics');
    var checker=new TypeChecker();
    eq(checker.check(source), types, 'static Int, Ratio, Float inference');
    ok(checker.signature('divide') == 'Div a b c => a -> b -> c',
      'annotated overloaded division has a concise relation signature');
    eq(new Vm(30000000).runPlain(source), expected,'Haxe AST VM');
    var compiled=BytecodeCompiler.compileSource(source);
    eq(new ByteVm(30000000).runPlain(compiled),expected,'Haxe bytecode VM');

    var vm=new Vm(40000000);
    vm.loadStdlib();
    var viaNail=vm.compileWithNail(source);
    var nailImage=BootstrapImage.encode(viaNail), hostImage=BootstrapImage.encode(compiled);
    var difference=0;
    while (difference < nailImage.length && difference < hostImage.length &&
        nailImage.charAt(difference)==hostImage.charAt(difference)) difference++;
    ok(nailImage==hostImage,
      'self-hosted compiler preserves modern numeric types and rows; '
      + 'first difference at '+difference
      + ' host='+hostImage.substr(difference,180)
      + ' nail='+nailImage.substr(difference,180));
    eq(new ByteVm(40000000).runPlain(viaNail),expected,'Nail bytecode execution');
    var boot=new BootRuntime(40000000);
    var sourceFree=boot.compile(source);
    ok(BootstrapImage.encode(sourceFree)==BootstrapImage.encode(compiled),
      'source-free compiler agrees with Haxe reference');
    eq(boot.runBytecode(sourceFree).map(Vm.toPlain),expected,
      'source-free modern runtime');

    var negative=[
      {code:'nail 0.45 ; 1 + 2.0 ;',error:'explicit conversion'},
      {code:'nail 0.45 ; 1 / 2.0 ;',error:'explicit conversion'},
      {code:'nail 0.45 ; toFloat 0.5 ;',error:'toFloat requires Int or Ratio'},
      {code:'nail 0.45 ; def f x y = x / y ;',error:'no Div instance'},
      {code:'nail 0.45 ; Div : Int Int Float ;',error:'unsupported Div row'},
      {code:'nail 0.45 ; Div : Int Int Ratio ; Div : Int Int Ratio ;',
        error:'duplicate Div input types'},
      {code:'nail 0.45 ; def bad x y : Div = x + y ;',
        error:'cannot unify'}
    ];
    for (item in negative) fails(() -> new TypeChecker().check(item.code),item.error);
    fails(() -> new Vm().run(header+'1 / 0 ;'),'Division by zero');
    fails(() -> new Vm().run(header+'1 + 2.0 ;'),'Mixed numeric domains');
    fails(() -> new Parser('nail 0.53 ; 1 ;').parseRaw(),'Unsupported Nail language version');
    fails(() -> new Parser('nail 0.45 ; nail 0.45 ;').parseRaw(),'Unexpected');
    eq(new TypeChecker().preview('0.1 + 0.2 ;'),['Number'],
      'legacy bootstrap source remains unaffected');
    trace('NailLang 0.45 numeric semantics: '+checks+' assertions passed');
  }
}
