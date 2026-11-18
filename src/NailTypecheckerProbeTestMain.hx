import haxe.Json;
import haxe.ds.StringMap;
import nail.Parser;
import nail.BootRuntime;
import nail.ResultValue;
import nail.Value;
import nail.TypeChecker;

/** End-to-end differential tests for the first Nail-written HM checker.
    The Nail checker is invoked via the source-free bytecode VM; it has no
    Haxe type-checker callback or privileged type primitive. */
class NailTypecheckerProbeTestMain {
  static var checks:Int=0;
  static function eq(a:Dynamic,b:Dynamic,label:String):Void {
    if (Json.stringify(a)!=Json.stringify(b))
      throw 'NAIL TYPECHECKER: '+label+' expected '+Json.stringify(b)+' got '+Json.stringify(a);
    checks++;
  }

  static function inspect(boot:BootRuntime,source:String):{ok:Bool,types:Array<String>,message:String} {
    var result=boot.invoke('tcCheckSource',Text(source));
    var tag=ResultValue.tag(result);
    if(tag==ResultValue.ERR)
      return switch(ResultValue.get(result,ResultValue.ERR)) {
        case Text(message): {ok:false,types:[],message:message};
        case _: throw 'Checker Error must contain Text';
      };
    var checked=ResultValue.get(result,ResultValue.OK);
    var values:Array<String>=[];
    switch(checked) {
      case SyntaxNode('TCChecked',Cons(_, _)) | SyntaxNode('TCChecked',Nil):
        var remaining:Value=switch(checked) {
          case SyntaxNode(_, xs): xs;
          case _: Nil;
        };
        while(true) switch(remaining) {
          case Nil: break;
          case Cons(item,tail):
            var shown=boot.invoke('tcPretty',item);
            switch shown {
              case Text(label): values.push(label);
              case _: throw 'tcPretty must return Text';
            }
            remaining=tail;
          case _: throw 'Checker returned invalid result list';
        }
      case _: throw 'Checker Ok must contain TCChecked';
    }
    return {ok:true,types:values,message:''};
  }

  static function checkGood(boot:BootRuntime,body:String,expected:Array<String>):Void {
    var source='nail 0.54 ; '+body;
    var found=inspect(boot,source);
    eq(found.ok,true,'expected checker success: '+body+' ('+found.message+')');
    eq(found.types,expected,'Nail result types: '+body);
    eq(new TypeChecker().check(source),expected,'Haxe parity: '+body);
  }

  static function checkBad(boot:BootRuntime,body:String,part:String):Void {
    var source='nail 0.54 ; '+body;
    var found=inspect(boot,source);
    eq(found.ok,false,'expected Nail rejection: '+body);
    if(found.message.indexOf(part)<0)
      throw 'NAIL TYPECHECKER: expected diagnostic '+part+', got '+found.message;
    checks++;
    var rejected=false;
    try new TypeChecker().check(source)
    catch(_:Dynamic) rejected=true;
    eq(rejected,true,'Haxe must also reject '+body);
  }

  static function checkStructural(boot:BootRuntime,body:String,expected:Array<String>):Void {
    var source='nail 0.54 ; '+body;
    var found=inspect(boot,source);
    eq(found.ok,true,'expected open-row success: '+body+' ('+found.message+')');
    eq(found.types,expected,'Nail open-record type: '+body);
    var parser=new Parser(source,new StringMap<Array<String>>());
    var checker=new TypeChecker();
    eq(checker.checkParsed(parser,parser.parse()),expected,
      'Haxe opt-in open-row parity: '+body);
  }

  static function rejectsStructural(boot:BootRuntime,body:String,reason:String):Void {
    var source='nail 0.54 ; '+body;
    var found=inspect(boot,source);
    eq(found.ok,false,'Nail must reject structural failure: '+body);
    if(found.message.indexOf(reason)<0)
      throw 'NAIL TYPECHECKER: expected '+reason+' got '+found.message;
    checks++;
    var parser=new Parser(source,new StringMap<Array<String>>());
    var checker=new TypeChecker();
    var rejected=false;
    try checker.checkParsed(parser,parser.parse()) catch(_:Dynamic) rejected=true;
    eq(rejected,true,'Haxe must reject same structural failure: '+body);
  }

  static function deferredNailFeature(boot:BootRuntime,body:String,reason:String,
      expectedHaxe:Array<String>):Void {
    var source='nail 0.54 ; '+body;
    var found=inspect(boot,source);
    eq(found.ok,false,'unsupported feature must not appear successfully checked');
    if(found.message.indexOf(reason)<0)
      throw 'NAIL TYPECHECKER: deferred '+reason+' got '+found.message;
    checks++;
    eq(new TypeChecker().check(source),expectedHaxe,
      'reference checker can handle the explicitly deferred feature');
  }

  static function main():Void {
    var boot=new BootRuntime(60000000);
    var unversioned=boot.invoke('tcCheckSource',Text('1 + 2 ;'));
    eq(ResultValue.tag(unversioned),ResultValue.ERR,
      'legacy numeric source is rejected until dialect-specific checking exists');
    checkGood(boot,'42 ;',['Int']);
    checkGood(boot,'true ;',['Bool']);
    checkGood(boot,'" Ciao " ;',['Text']);
    checkGood(boot,'if true then 1 else 2 ;',['Int']);
    checkGood(boot,'( fun x -> x ) 42 ;',['Int']);
    checkGood(boot,'def id x = x ; id 7 ; id true ;',['Int','Bool']);
    checkGood(boot,'let id = fun x -> x in id " Hello " ;',['Text']);
    checkGood(boot,'def f x = if x then f false else true ; f true ;',['Bool']);
    checkGood(boot,'textConcat " A " " B " ;',['Text']);
    checkGood(boot,'7 + 5 ;',['Int']);
    checkGood(boot,'7 - 5 ;',['Int']);
    checkGood(boot,'7 * 5 ;',['Int']);
    checkGood(boot,'7 / 5 ;',['Ratio']);
    checkGood(boot,'1.25 + 0.5 ;',['Float']);
    checkGood(boot,'1.25 / 0.5 ;',['Float']);
    checkGood(boot,'( 3 / 2 ) + 1 ;',['Ratio']);
    checkBad(boot,'1 + 0.5 ;','No numeric relation instance');
    checkBad(boot,'def add x y = x + y ;','concrete types');
    checkGood(boot,'1 == 2 ;',['Bool']);
    checkGood(boot,'" A " != " B " ;',['Bool']);
    checkGood(boot,'[ 1 , 2 ] == [ 1 , 3 ] ;',['Bool']);
    checkGood(boot,'{ x = 1 , y = true } == { x = 2 , y = false } ;',['Bool']);
    checkBad(boot,'1 == true ;','Type mismatch');
    checkBad(boot,'( fun x -> x ) == ( fun y -> y ) ;',
      'Eq constraints');
    checkBad(boot,'[ 1 ] == [ true ] ;','Type mismatch');
    var qualifiedEqSource='nail 0.54 ; '
      +'def same x y = x == y ; same 3 3 ;';
    var qualifiedEq=inspect(boot,qualifiedEqSource);
    eq(qualifiedEq.ok,false,
      'generic equality must be rejected until qualified HM schemes exist');
    if(qualifiedEq.message.indexOf('Eq constraints')<0)
      throw 'NAIL TYPECHECKER: unexpected qualified Eq diagnostic '+qualifiedEq.message;
    checks++;
    eq(new TypeChecker().check(qualifiedEqSource),['Bool'],
      'reference checker already supports polymorphic Eq constraints');
    checkGood(boot,'[ 1 , 2 , 3 ] ;',['[Int]']);
    checkGood(boot,'head [ 1 , 2 ] ;',['Int']);
    checkBad(boot,'[ 1 , true ] ;','Type mismatch');

    checkBad(boot,'unknownVar ;','Unknown name');
    checkBad(boot,'1 2 ;','Type mismatch');
    checkBad(boot,'if 1 then true else false ;','Type mismatch');
    checkBad(boot,'if true then 1 else false ;','Type mismatch');
    checkBad(boot,'fun x -> x x ;','Recursive type');

    checkStructural(boot,'( { x = 1 , y = true } ) . x ;',['Int']);
    checkStructural(boot,'def getX r = r . x ; getX { x = 5 , y = true } ;',['Int']);
    checkStructural(boot,'def getX r = r . x ; getX { x = 5 } ;',['Int']);
    checkStructural(boot,
      'def sum r = textConcat ( r . x ) ( r . y ) ; '
      +'sum { x = " Left " , y = " Right " } ;',
      ['Text']);
    rejectsStructural(boot,'def getX r = r . x ; getX { y = true } ;',
      'Missing structural field');
    rejectsStructural(boot,
      'def getX r = textConcat ( r . x ) " S " ; '
      +'getX { x = true } ;',
      'Type mismatch');
    var htmlContract='type Html = { h2 : Text Text , div : Text Text } ; ';
    checkStructural(boot,htmlContract
      +'def html = { h2 = fun x -> textConcat " H: " x , '
      +'div = fun x -> x } ; '
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'render html " Test " ;',['Text']);
    checkStructural(boot,htmlContract
      +'def render ( html : Html ) ( title : Text ) = html { h2 title } ; '
      +'render { h2 = fun x -> x , div = fun x -> x , extra = true } '
      +'" Typed " ;',['Text']);
    checkStructural(boot,htmlContract
      +'def html : Html = { h2 = fun x -> x , div = fun x -> x } ; '
      +'html . h2 " Value " ;',['Text']);
    rejectsStructural(boot,htmlContract
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'render { h2 = fun x -> x } " Missing " ;',
      'Missing structural field');
    rejectsStructural(boot,htmlContract
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'render { h2 = fun x -> true , div = fun x -> x } " Wrong " ;',
      'Type mismatch');
    rejectsStructural(boot,'type Html = { h2 : UnknownType Text } ; '
      +'def render ( html : Html ) = html { h2 " X " } ;',
      'Unknown type');
    checkGood(boot,'Add : Int Int Int ; Add : Float Float Float ; '
      +'def add x y : Add = x + y ; add 6 7 ; add 1.25 0.5 ;',
      ['Int','Float']);
    checkGood(boot,'Div : Int Int Ratio ; Div : Float Float Float ; '
      +'def divide x y : Div = x / y ; divide 7 2 ; divide 7.0 2.0 ;',
      ['Ratio','Float']);
    checkGood(boot,'Merge : Text Text Text ; '
      +'def merge a b : Merge = textConcat a b ; '
      +'merge " A " " B " ;',['Text']);
    checkBad(boot,'Add : Int Int Ratio ; '
      +'def wrong a b : Add = a + b ;','Type mismatch');
    checkBad(boot,'Add : Int Int Int ; Add : Int Int Int ; '
      +'def add x y : Add = x + y ;',
      'Duplicate relation input types');
    checkBad(boot,'Add : Int Int Int ; '
      +'def add x y : Add = x + y ; add 1.0 2.0 ;',
      'No relation instance');
    checkGood(boot,
      'Join3 : Text Text Text Text ; '
      +'def join3 a b c : Join3 = textConcat ( textConcat a b ) c ; '
      +'join3 " A " " B " " C " ;',['Text']);
    checkGood(boot,
      'Pick : Text Int Bool Text ; Pick : Bool Text Int Bool ; '
      +'def pick x y z : Pick = x ; '
      +'pick " A " 5 true ; pick false " B " 6 ;',
      ['Text','Bool']);
    checkGood(boot,
      'Len : Text Int ; '
      +'def len x : Len = textLengthInt x ; '
      +'len " Hello " ;',['Int']);
    checkGood(boot,
      'Join4 : Text Text Text Text Text ; '
      +'def join4 a b c d : Join4 = '
      +'textConcat ( textConcat a b ) ( textConcat c d ) ; '
      +'join4 " A " " B " " C " " D " ;',['Text']);
    checkBad(boot,
      'Pick : Text Int Bool Text ; Pick : Text Int Bool Bool ; '
      +'def pick x y z : Pick = x ;',
      'Duplicate relation input types');
    checkBad(boot,
      'Pick : Text Int Bool Text ; Pick : Text Int Text ; '
      +'def pick x y z : Pick = x ;',
      'Inconsistent relation arity');
    checkBad(boot,
      'Join3 : Text Text Text Text ; '
      +'def join3 a b : Join3 = textConcat a b ;',
      'Relation definition arity');
    checkBad(boot,
      'Join3 : Text Text Text Text ; '
      +'def join3 a b c d : Join3 = textConcat a b ;',
      'Relation definition arity');
    checkBad(boot,
      'Pick : Text Int Bool Text ; '
      +'def pick x y z : Pick = x ; '
      +'pick " A " true 5 ;',
      'No relation instance');
    var params=[for(i in 1...17) 'p'+i];
    var signature=[for(i in 0...17) 'Text'].join(' ');
    var values=[for(i in 0...16) '" T "'].join(' ');
    checkGood(boot,
      'Wide : '+signature+' ; '
      +'def wide '+params.join(' ')+' : Wide = p1 ; '
      +'wide '+values+' ;',['Text']);
    trace('Nail-written typechecker core: '+checks+' differential checks passed');
  }
}
