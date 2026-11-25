import haxe.Json;
import haxe.Resource;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.Parser;
import nail.Vm;
import nail.TypeChecker;
import nail.ResultValue;
import nail.Value;

/** Isolated first step of self-parser alignment. Compare the surface lowering with the Haxe oracle. */
class SelfSyntaxExperimentTestMain {
  static var passed=0;
  static function ok(condition:Bool,label:String):Void {
    if (!condition) throw 'SELF SYNTAX: '+label;
    passed++;
  }
  static function checkTypes(library:Vm,body:String,expected:Array<String>):Void {
    var source='nail 0.61 ; '+body;
    var result=library.invoke('tcCheckSource',Text(source));
    ok(ResultValue.tag(result)==ResultValue.OK,'deferred numeric checker: '+body+' got '+Std.string(result));
    var types:Array<String>=[];
    var rest=switch(ResultValue.get(result,ResultValue.OK)) {
      case SyntaxNode('TCChecked',items): items;
      case _: throw 'Expected TCChecked';
    };
    while(true) switch(rest) {
      case Nil: break;
      case Cons(item,tail):
        switch(library.invoke('tcPretty',item)) {
          case Text(label): types.push(label);
          case _: throw 'Expected type text';
        }
        rest=tail;
      case _: throw 'Invalid TCChecked list';
    }
    ok(Json.stringify(types)==Json.stringify(expected),'Nail inferred types '+body);
    ok(Json.stringify(new TypeChecker().checkExperimental(source))==Json.stringify(expected),'Haxe inferred types '+body);
  }
  static function rejectNumeric(library:Vm,body:String,fragment:String):Void {
    var result=library.invoke('tcCheckSource',Text('nail 0.61 ; '+body));
    ok(ResultValue.tag(result)==ResultValue.ERR,'expected numeric rejection '+body);
    switch(ResultValue.get(result,ResultValue.ERR)) {
      case Text(message): ok(message.indexOf(fragment)>=0,'numeric diagnostic '+message);
      case _: throw 'Expected error text';
    }
  }
  static function main():Void {
    var source=Resource.getString('stdlib-experimental');
    if (source==null) throw 'Missing experimental stdlib';
    var library=new Vm(70000000);
    library.runExperimental(source);
    var samples:Array<{code:String,expected:Array<Dynamic>}>=[
      {code:'def add-one x = x + 1 ; 41 >> add-one ;',expected:[42]},
      {code:'def double-it x = x * 2 ; 1 + 2 >> double-it >> double-it ;',expected:[12]},
      {code:'def subtract-from a b = a - b ; 3 >> subtract-from 10 ;',expected:[7]},
      {code:'def keep-1 x = x ; 2 >> ( fun x -> keep-1 ( x + 1 ) ) ;',expected:[3]},
      {code:'def pass-through x = x ; " >> " >> pass-through ;',expected:['>>']},
      {code:'def choose-it x = x ; if true then 2 >> choose-it else 0 ;',expected:[2]}
    ];
    for (sample in samples) {
      var oracle=new Vm(70000000).runPlainExperimental(sample.code);
      ok(Json.stringify(oracle)==Json.stringify(sample.expected),'host expected '+sample.code);
      ok(Json.stringify(library.runPlainWithNail(sample.code))==Json.stringify(oracle),
        'Nail evaluator agrees '+sample.code);
      var host=BytecodeCompiler.compile(new Parser(sample.code,null,true).parse());
      ok(BootstrapImage.encode(host)==BootstrapImage.encode(library.compileWithNail(sample.code)),
        'Nail compiler bytecode agrees '+sample.code);
    }
    for (code in ['def bad--name x = x ;','def bad- x = x ;','def -bad x = x ;',
      '1 >> ;','def pair x y = x ; pair z: 2 ;']) {
      var refused=false;
      try library.runPlainWithNail(code) catch (_:Dynamic) refused=true;
      ok(refused,'unsupported or malformed syntax rejected '+code);
    }
    var namedSamples:Array<{code:String,expected:Array<Dynamic>,direct:Bool}>=[
      {code:'def pair first: a second: b = a * 10 + b ; pair first: 4 second: 2 ;',expected:[42],direct:true},
      {code:'def combine a b = a * 10 + b ; combine 4 b: 2 ; combine a: 4 2 ;',expected:[42,42],direct:true},
      {code:'def combine a b = a * 10 + b ; combine b: 2 a: 4 ; combine b: 2 4 ;',expected:[42,42],direct:false},
      {code:'def fraction numerator: a denominator: b = a / b ; def half = fraction denominator: 2 ; half 3 ;',expected:[1.5],direct:false},
      {code:'def pair a b = a * 10 + b ; 4 >> pair b: 2 ;',expected:[42],direct:false},
      {code:'def pair a b = a * 10 + b ; pair b: ( pair b: 2 a: 0 ) a: 4 ;',expected:[42],direct:false},
      {code:'def make a = fun b -> a + b ; make a: 40 2 ;',expected:[42],direct:true},
      {code:'def factorial n = if n == 0 then 1 else n * factorial n: ( n - 1 ) ; factorial n: 5 ;',expected:[120],direct:true},
      {code:'def one a b = a ; let one = ( fun a -> a ) in one 42 ; one a: 42 b: true ;',expected:[42,42],direct:true}
    ];
    for (sample in namedSamples) {
      // Each sample owns its definitions; the compiler environment is shared
      // but evaluation must not redefine the same names across samples.
      var oracle=new Vm(70000000).runPlainExperimental(sample.code);
      ok(Json.stringify(oracle)==Json.stringify(sample.expected),'host named expected '+sample.code);
      var code=library.compileWithNail(sample.code);
      var bytes=new nail.ByteVm(70000000);
      ok(Json.stringify(bytes.runPlain(code))==Json.stringify(oracle),'Nail named bytecode result '+sample.code);
      if (sample.direct) {
        var host=BytecodeCompiler.compile(new Parser(sample.code,null,true).parse());
        ok(BootstrapImage.encode(host)==BootstrapImage.encode(code),'ordered named bytecode identical '+sample.code);
      }
    }
    for (code in [
      'macro f a: a = quote ( unquote a ) ;',
      'def duplicate same: a same: b = a ;',
      'def duplicate first: a second: a = a ;',
      'def f first: a = a ; f a: 42 ;',
      'def f a b = a ; f a: 1 a: 2 ;',
      'def f a b = a ; f 1 a: 2 ;',
      'missing a: 1 ;',
      'def f a b = a ; def wrapper f = f a: 1 ;',
      'def f a b = a ; let f = ( fun x -> x ) in f a: 1 ;',
      'def f a b = a ; ( fun f -> f a: 1 ) f ;',
      'def f a b = a ; match [ 1 ] with | [] -> 0 | f :: rest -> f a: 1 ;'
    ]) {
      var refused=false;
      try library.compileWithNail(code) catch (_:Dynamic) refused=true;
      // Compiler may return an Error Syntax value rather than throw.
      if (!refused) switch(library.compileWithNail(code)) {
        case nail.Value.SyntaxLeaf('Error',_): refused=true;
        case _: 
      }
      ok(refused,'Nail named syntax rejects '+code);
    }
    var modern='nail 0.61 ; def fraction numerator: ( a : Int ) denominator: ( b : Int ) = a / b ; fraction numerator: 3 denominator: 2 ;';
    var modernHost=new Vm(70000000).runPlainExperimental(modern);
    ok(Json.stringify(modernHost)==Json.stringify(['R:3/2']),'modern typed oracle');
    ok(Json.stringify(new nail.ByteVm(70000000).runPlain(library.compileWithNail(modern)))==Json.stringify(modernHost),
      'modern annotated public labels preserve exact division');
    var stable=new Vm(70000000);
    stable.loadStdlib();
    for (code in ['def new-name x = x ;','1 >> ( fun x -> x ) ;']) {
      var refused=false;
      try stable.runPlainWithNail(code) catch (_:Dynamic) refused=true;
      ok(refused,'official self-parser remains unchanged '+code);
    }
    checkTypes(library,'( fun x -> x + 1 ) 2 ;',['Int']);
    checkTypes(library,'( fun x -> x / 2 ) 3 ;',['Ratio']);
    checkTypes(library,'( fun x -> ( x + 1 ) / 2 ) 3 ;',['Ratio']);
    checkTypes(library,'def add-one ( x : Int ) = x + 1 ; add-one 41 ;',['Int']);
    checkTypes(library,'def fraction numerator: ( a : Int ) denominator: ( b : Int ) = a / b ; fraction denominator: 2 numerator: 3 ;',['Ratio']);
    checkTypes(library,'( fun x -> let y = x + 1 in y + 2 ) 3 ;',['Int']);
    checkTypes(library,'( fun x -> x + x ) 1.5 ;',['Float']);
    rejectNumeric(library,'( fun x -> x + 1 ) true ;','No numeric relation instance');
    rejectNumeric(library,'( fun x -> x + 1 ) 1.5 ;','No numeric relation instance');
    rejectNumeric(library,'def summ x y = x + y ;','Ambiguous numeric constraint');
    rejectNumeric(library,'def add-one ( x : Text ) = x + 1 ;','No numeric relation instance');
    trace('Self syntax experiment: '+passed+' differential checks passed');
  }
}
