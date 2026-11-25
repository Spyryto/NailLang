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
  // Inspect the actual generalized scheme, not only the result of a
  // concrete application (which could also pass without propagation).
  static function checkNumericScheme(library:Vm,body:String,name:String,expected:String):Void {
    var source='nail 0.61 ; '+body;
    var result=library.invoke('tcCheckSourceSchemes',Text(source));
    ok(ResultValue.tag(result)==ResultValue.OK,'scheme inference '+body);
    var scheme=switch(ResultValue.get(result,ResultValue.OK)) {
      case SyntaxNode('TCCheckedSchemes',Cons(_,Cons(SyntaxNode('TCExportSchemes',Cons(SyntaxNode('TCBinding',Cons(_,Cons(value,Nil))),Nil)),Nil))): value;
      case _: throw 'Expected a single checked definition scheme';
    };
    var term=switch(scheme) {
      case SyntaxNode('TCScheme',Cons(value,_)): value;
      case _: throw 'Expected TCScheme';
    };
    var output=switch(term) {
      case SyntaxNode('TCFun',Cons(_,Cons(SyntaxLeaf('TCBase',label),Nil))): label;
      case _: throw 'Expected concrete codomain: '+Std.string(term);
    };
    ok(output==expected,'Nail common numeric result '+body);
    var checker=new TypeChecker();
    checker.checkExperimental(source);
    ok(StringTools.endsWith(checker.signature(name),' -> '+expected),'Haxe common numeric result '+body);
    var predicates=library.invoke('tcSchemeNumeric',scheme);
    ok(switch(predicates) {case Cons(_,_):true;case _:false;},'remaining numeric obligation is retained');
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
    checkTypes(library,'def summ x y = x + y ; summ 2 3 ; summ 1.5 2.5 ; summ ( 1 / 2 ) 3 ;',['Int','Float','Ratio']);
    checkTypes(library,'def summ x y = x + y ; def add-three = summ y: 3 ; add-three 10 ; add-three ( 1 / 2 ) ;',['Int','Ratio']);
    checkTypes(library,'def summ x y = x + y ; def add-three = summ 3 ; add-three 10 ;',['Int']);
    checkTypes(library,'def summ x y = x + y ; def twice x = summ x x ; twice 2 ; twice 1.5 ;',['Int','Float']);
    checkTypes(library,'def fraction numerator: a denominator: b = a / b ; def half = fraction denominator: 2 ; half 3 ;',['Ratio']);
    checkTypes(library,'def f x = let y = x + 1 in y + 2 ; f 3 ;',['Int']);
    checkTypes(library,'def summ x y = x + y ; def apply f x = f x ; apply ( summ y: 3 ) 10 ;',['Int']);
    checkTypes(library,'let twice = ( fun x -> x + x ) in let ignored = twice 1 in twice 1.5 ;',['Float']);
    rejectNumeric(library,'def summ x y = x + y ; summ true 3 ;','No numeric relation instance');
    rejectNumeric(library,'def summ x y = x + y ; summ 1.5 3 ;','No numeric relation instance');
    rejectNumeric(library,'def summ x y = x + y ; def add-three = summ y: 3 ; add-three true ;','No numeric relation instance');
    rejectNumeric(library,'def summ x y = x + y ; summ ;','Ambiguous numeric constraint');
    // Check the private/public boundary using the ordinary curried call.
    checkTypes(library,'def f x = let y = x + 1 in let twice = ( fun z -> z + z ) in let ignored = twice 1 in twice 1.5 ; f 3 ;',['Float']);
    checkTypes(library,'def f x = let y = x + 1 in let id = ( fun z -> z ) in let ignored = id true in id y ; f 3 ;',['Int']);
    rejectNumeric(library,'def f x = let y = x + 1 in if true then y else 1.5 ; f 3 ;','No numeric relation instance');
    var wire=library.run('tcCanonicalCheckedDefinition " nail 0.61 ; def summ x y = x + y ; " " summ " ;')[0];
    ok(ResultValue.tag(wire)==ResultValue.ERR,'public row evidence cannot discard numeric predicates');
    rejectNumeric(library,'def add-one ( x : Text ) = x + 1 ;','No numeric relation instance');
    checkNumericScheme(library,'def half x = x / 2 ;','half','Ratio');
    checkNumericScheme(library,'def add-half x = x + ( 1 / 2 ) ;','add-half','Ratio');
    checkNumericScheme(library,'def chain x = ( x / 2 ) + 1 ;','chain','Ratio');
    checkTypes(library,'def half x = x / 2 ; half 3 ; half ( 3 / 2 ) ;',['Ratio','Ratio']);
    rejectNumeric(library,'def half x = x / 2 ; half 1.5 ;','No numeric relation instance');
    rejectNumeric(library,'def half x = x / 2 ; half ;','Ambiguous numeric constraint');
    checkTypes(library,'1 < 2 ; 1 <= 2 ; 2 > 1 ; 2 >= 1 ;',['Bool','Bool','Bool','Bool']);
    checkTypes(library,'( 1 / 2 ) < 1 ; 1 >= ( 1 / 2 ) ; 1.5 <= 2.5 ;',['Bool','Bool','Bool']);
    checkTypes(library,'def less a b = a < b ; less 1 2 ; less 1.5 2.5 ; less ( 1 / 2 ) 3 ;',['Bool','Bool','Bool']);
    checkNumericScheme(library,'def small x = x < 2 ;','small','Bool');
    checkTypes(library,'def small x = x < 2 ; small 1 ; small ( 1 / 2 ) ;',['Bool','Bool']);
    checkTypes(library,'def bounded x = if x >= 0 then x + 1 else x ; bounded 2 ;',['Int']);
    rejectNumeric(library,'1 < 1.5 ;','No numeric relation instance');
    rejectNumeric(library,'true > false ;','No numeric relation instance');
    rejectNumeric(library,'def less a b = a < b ; less 1 2.5 ;','No numeric relation instance');
    rejectNumeric(library,'def small x = x < 2 ; small true ;','No numeric relation instance');
    trace('Self syntax experiment: '+passed+' differential checks passed');
  }
}
