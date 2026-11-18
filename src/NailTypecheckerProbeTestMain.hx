import haxe.Json;
import haxe.ds.StringMap;
import nail.Parser;
import nail.MacroExpander;
import nail.SyntaxEncoder;
import nail.BootRuntime;
import nail.ResultValue;
import nail.Value;
import nail.TypeChecker;
import nail.NailSourceAnalysis;

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
    return inspectResult(boot,boot.invoke('tcCheckSource',Text(source)));
  }

  /** Differential probe for already macro-expanded surface Syntax. This
      isolates Nail's HM checker from the Haxe macro expansion oracle. */
  static function inspectExpanded(boot:BootRuntime,source:String):{ok:Bool,types:Array<String>,message:String} {
    var parser=new Parser(source);
    var parsed=SyntaxEncoder.program(parser.parse());
    var expanded=MacroExpander.syntax(parsed);
    // The Haxe modern parser already emits Int/Ratio/Float literal Syntax:
    // rewriting a second time would visit typed literal leaves incorrectly.
    return inspectResult(boot,boot.invoke('tcCheckSyntax',expanded));
  }

  static function inspectResult(boot:BootRuntime,result:Value):{ok:Bool,types:Array<String>,message:String} {
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

  static function checkMacroGood(boot:BootRuntime,body:String,expected:Array<String>):Void {
    var source='nail 0.54 ; '+body;
    var found=inspectExpanded(boot,source);
    eq(found.ok,true,'expanded Nail macro success: '+body+' ('+found.message+')');
    eq(found.types,expected,'expanded Nail macro types: '+body);
    eq(new TypeChecker().check(source),expected,'Haxe hygienic macro parity: '+body);
  }

  static function checkMacroBad(boot:BootRuntime,body:String,reason:String):Void {
    var source='nail 0.54 ; '+body;
    var found=inspectExpanded(boot,source);
    eq(found.ok,false,'expanded Nail macro must reject: '+body);
    if(found.message.indexOf(reason)<0)
      throw 'NAIL TYPECHECKER: macro expected '+reason+' got '+found.message;
    checks++;
    var rejected=false;
    try new TypeChecker().check(source) catch(_:Dynamic) rejected=true;
    eq(rejected,true,'Haxe must reject expanded macro source: '+body);
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
      'Eq constraint');
    checkBad(boot,'[ 1 ] == [ true ] ;','Type mismatch');
    checkGood(boot,
      'def same x y = x == y ; same 3 3 ; same true false ; '
      +'same " A " " B " ;',
      ['Bool','Bool','Bool']);
    checkGood(boot,
      'def same x y = x == y ; '
      +'same [ 1 , 2 ] [ 1 , 3 ] ; '
      +'same [ true ] [ false ] ;',
      ['Bool','Bool']);
    checkGood(boot,
      'def same x y = x == y ; '
      +'let compare = same in [ compare 1 2 , compare " A " " B " ] ;',
      ['[Bool]']);
    checkGood(boot,
      'def same x y = x == y ; def eqList xs ys = same xs ys ; '
      +'eqList [ 1 ] [ 2 ] ; eqList [ true ] [ false ] ;',
      ['Bool','Bool']);
    checkGood(boot,
      'def same x y = x == y ; '
      +'same { x = 1 , y = true } { x = 1 , y = false } ;',
      ['Bool']);
    checkGood(boot,
      'def reflexive x = x == x ; '
      +'reflexive 11 ; reflexive " Echo " ;',
      ['Bool','Bool']);
    checkGood(boot,
      'def makeEq x = fun y -> x == y ; '
      +'makeEq 1 2 ; makeEq " Yes " " No " ;',
      ['Bool','Bool']);
    checkGood(boot,
      'def listEq xs ys = xs == ys ; '
      +'listEq [ { x = 1 } ] [ { x = 2 } ] ;',
      ['Bool']);
    checkBad(boot,
      'def makeEq x = fun y -> x == y ; '
      +'makeEq ( fun x -> x ) ( fun y -> y ) ;',
      'Eq constraint');
    checkBad(boot,
      'def same x y = x == y ; same 1 " Mismatch " ;',
      'Type mismatch');
    checkBad(boot,
      'def same x y = x == y ; '
      +'same ( fun a -> a ) ( fun b -> b ) ;',
      'Eq constraint');
    checkBad(boot,
      'def same x y = x == y ; '
      +'same [ fun x -> x ] [ fun y -> y ] ;',
      'Eq constraint');
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
    var person='type Person { name Text age Int } ; ';
    var box='type Box a { value a } ; ';
    var pair='type Pair a b { first a second b } ; ';
    checkGood(boot,person+'( Person " Ada " 36 ) . name ;',['Text']);
    checkGood(boot,person+'( Person { age = 36 , name = " Ada " } ) . age ;',
      ['Int']);
    checkGood(boot,person+'def read p = p . name ; read ( Person " C " 12 ) ;',
      ['Text']);
    checkGood(boot,box+'( Box true ) . value ; ( Box 7 ) . value ;',
      ['Bool','Int']);
    checkGood(boot,box+'def wrap x = Box x ; '
      +'( wrap 42 ) . value ; ( wrap false ) . value ;',
      ['Int','Bool']);
    checkGood(boot,pair+'( Pair 9 true ) . first ; '
      +'( Pair " Y " 6 ) . second ;',['Int','Int']);
    checkGood(boot,person+'type Badge { owner Person valid Bool } ; '
      +'( Badge { valid = true , owner = Person " Jo " 9 } ) . owner . age ;',
      ['Int']);
    checkGood(boot,box+'Box 1 == Box 2 ;',['Bool']);
    checkBad(boot,person+'Person true 1 ;','Type mismatch');
    checkBad(boot,person+'Person { name = " Ada " } ;',
      'Nominal record field count mismatch');
    checkBad(boot,person+'Person { name = " Ada " , invalid = 2 } ;',
      'Missing named record field');
    checkBad(boot,box+'Box ( fun x -> x ) == Box ( fun y -> y ) ;',
      'Eq constraint');
    checkBad(boot,'type A { value Int } ; type B { value Int } ; '
      +'if true then A 1 else B 2 ;','Type mismatch');
    checkBad(boot,'type Person { name Text } ; '
      +'type Company { name Text } ; '
      +'def get x = x . name ;',
      'Ambiguous nominal record field');
    checkBad(boot,'type Box a { value a } ; '
      +'type Holder { inner Box } ;',
      'Parameterized nominal field');
    checkBad(boot,'type Plain { value Int } ; '
      +'( Plain true ) . value ;','Type mismatch');

    var option='type Option a = None | Some a ; ';
    checkGood(boot,'type Color = Red | Blue ; Red ; Blue ;',
      ['Color','Color']);
    checkGood(boot,'type Color = Red | Blue ; '
      +'if true then Red else Blue ;',['Color']);
    checkGood(boot,option+'Some 42 ; Some true ;',
      ['Option[Int]','Option[Bool]']);
    checkGood(boot,option+'Some 3 == Some 4 ;',['Bool']);
    checkGood(boot,'type Tree = Leaf Int | Branch Tree Tree ; '
      +'Branch ( Leaf 1 ) ( Leaf 2 ) ;',['Tree']);
    checkGood(boot,'type Reply a e = Success a | Failure e ; '
      +'def result x = if true then Success x else Failure " Fail " ; '
      +'result 4 ;',['Reply[Int, Text]']);
    checkBad(boot,option+'Some 4 true ;','Type mismatch');
    checkBad(boot,option+'Some true == Some 3 ;','Type mismatch');
    checkBad(boot,'type First = A | B ; type Second = C | D ; '
      +'if true then A else C ;','Type mismatch');
    checkBad(boot,option+'type Other a = Some a ;',
      'Duplicate sum constructor');

    // Lowered list patterns retain ordinary HM types; generated helpers are
    // typed by Nail, not delegated to the Haxe reference checker.
    checkGood(boot,'def firstOr fallback = function '
      +'| [] -> fallback | item :: rest -> item ; '
      +'firstOr 3 [ 4 , 5 ] ; firstOr 3 [] ;',['Int','Int']);
    checkGood(boot,'match [ 9 , 8 ] with '
      +'| [] -> 0 | first :: rest -> first ;',['Int']);
    checkBad(boot,'def broken = function '
      +'| [] -> 0 | first :: rest -> true ;',
      'Type mismatch');

    // Nominal patterns: coverage, binding arity and constructor ownership
    // are checked before the private #sumFail fallback is inferred.
    checkGood(boot,'type Color = Red | Blue ; '
      +'match Red with | Red -> 1 | Blue -> 2 ;',['Int']);
    checkGood(boot,option+'def unwrap = function '
      +'| None -> 0 | Some value -> value ; '
      +'unwrap ( Some 42 ) ;',['Int']);
    checkGood(boot,'type Status = Rest | Played Int ; '
      +'def tempo = function | Rest -> 0 | Played bpm -> bpm ; '
      +'tempo ( Played 116 ) ;',['Int']);
    checkGood(boot,option+'def classify = function '
      +'| None -> false | Some xs -> '
      +'( function | [] -> false | first :: rest -> true ) xs ; '
      +'classify ( Some [ 3 ] ) ;',['Bool']);
    checkBad(boot,option+'def partial = function '
      +'| Some value -> true ;','Non-exhaustive match');
    checkBad(boot,option+'def wrongArity = function '
      +'| None -> false | Some -> true ;',
      'Constructor match binding arity mismatch');
    checkBad(boot,'type First = One ; type Second = Two ; '
      +'def mixed = function | One -> 1 | Two -> 2 ;',
      'Mixed constructors');
    checkBad(boot,option+'def unknown = function '
      +'| None -> 0 | NotDeclared x -> x ;',
      'Unknown algebraic constructor');

    // Hygienic macro expansion adds private #macro_local_ subject binders
    // and #macro_global_ references to predicates, accessors and helpers.
    // The Nail type checker must preserve the original global binding.
    checkMacroGood(boot,option
      +'macro unwrap p = quote ( match unquote p with '
      +'| None -> 0 | Some value -> value ) ; '
      +'expand unwrap ( Some 42 ) ;',['Int']);
    checkMacroGood(boot,'type Color = Red | Blue ; '
      +'macro color x = quote ( match unquote x with '
      +'| Red -> " R " | Blue -> " B " ) ; '
      +'expand color Blue ;',['Text']);
    checkMacroGood(boot,option
      +'macro makeUnwrapper = quote ( function '
      +'| None -> 0 | Some item -> item ) ; '
      +'def unwrap = expand makeUnwrapper ; unwrap ( Some 21 ) ;',['Int']);
    checkMacroGood(boot,'def helper x = x ; '
      +'macro applyHelper arg = quote ( helper ( unquote arg ) ) ; '
      +'let helper = fun x -> true in expand applyHelper 42 ;',['Int']);
    checkMacroBad(boot,option
      +'macro missingCase x = quote ( match unquote x with '
      +'| Some item -> item ) ; '
      +'expand missingCase ( Some 1 ) ;','Non-exhaustive match');
    checkMacroBad(boot,'type One = Only ; type Two = Other ; '
      +'macro mixed x = quote ( match unquote x with '
      +'| Only -> 1 | Other -> 2 ) ; '
      +'expand mixed Only ;','Mixed constructors');

    // Full Nail source path: preserve static type metadata while expanding
    // macros before HM inference, without Haxe-side AST preparation.
    checkGood(boot,option
      +'macro unwrap p = quote ( match unquote p with '
      +'| None -> 0 | Some value -> value ) ; '
      +'expand unwrap ( Some 42 ) ;',['Int']);
    checkGood(boot,'def helper x = x ; '
      +'macro applyHelper arg = quote ( helper ( unquote arg ) ) ; '
      +'let helper = fun x -> true in expand applyHelper 42 ;',['Int']);
    checkGood(boot,'type Box a { value a } ; '
      +'macro makeBox x = quote ( Box ( unquote x ) ) ; '
      +'( expand makeBox 7 ) . value ;',['Int']);
    checkStructural(boot,'def id ( x : Int ) = x ; '
      +'macro callId x = quote ( id ( unquote x ) ) ; '
      +'expand callId 42 ;',['Int']);
    checkGood(boot,'Add : Int Int Int ; '
      +'macro sumInt x = quote ( unquote x + 1 ) ; '
      +'expand sumInt 9 ;',['Int']);
    checkBad(boot,option
      +'macro partial p = quote ( match unquote p with '
      +'| Some x -> x ) ; expand partial ( Some 1 ) ;',
      'Non-exhaustive match');
    checkBad(boot,'macro broken x = quote ( unquote missing ) ; '
      +'expand broken 1 ;','unknown unquote parameter');

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
    // The diagnostic adapter must use Nail's checker result, never run the
    // host TypeChecker or a second parser to invent source coordinates.
    var report=NailSourceAnalysis.analyze(
      'nail 0.54 ; def id x = x ; id 7 ;',boot);
    eq(report.ok,true,'Nail source report succeeds');
    eq(report.types,['Int'],'Nail report retains inferred evaluations');
    eq(report.diagnostics.length,0,'success has no diagnostics');

    var missingSource='nail 0.54 ;\ndef broken = missing ;';
    report=NailSourceAnalysis.analyze(missingSource,boot);
    eq(report.ok,false,'Nail report rejects unknown identifier');
    eq(report.diagnostics[0].phase,'type','Nail diagnostic phase');
    eq(report.diagnostics[0].span != null,true,
      'unique unknown identifier receives original location: '
        +Json.stringify(report));
    eq(report.diagnostics[0].span.start,missingSource.indexOf('missing'),
      'unknown identifier original UTF-16 offset');
    eq(report.diagnostics[0].span.line,2,'unknown identifier line');
    eq(report.diagnostics[0].span.column,14,'unknown identifier column');

    var commented='nail 0.54 ; # missing in a comment\n'
      +'def broken = missing ; " missing " ;';
    report=NailSourceAnalysis.analyze(commented,boot);
    eq(report.diagnostics[0].span != null,true,
      'quoted text and comments are excluded from matching');
    eq(report.diagnostics[0].span.start,commented.indexOf('missing ;'),
      'unknown identifier excludes comment/quoted occurrences');

    var repeated='nail 0.54 ; def bad = missing ; def later = missing ;';
    report=NailSourceAnalysis.analyze(repeated,boot);
    eq(report.diagnostics[0].span != null,true,
      'Nail fault trail disambiguates repeated identifiers across forms');
    eq(report.diagnostics[0].span.start,repeated.indexOf('missing'),
      'error resolves to first failing declaration, not the later occurrence');

    var repeatedInOne='nail 0.54 ; def bad = if true then missing else missing ;';
    report=NailSourceAnalysis.analyze(repeatedInOne,boot);
    eq(report.diagnostics[0].span != null,true,
      'Nail expression path disambiguates repeated identifiers in one form');
    eq(report.diagnostics[0].span.start,repeatedInOne.indexOf('missing'),
      'then-branch is visited before else-branch');

    var numericOperands='nail 0.54 ; def bad = missing + missing ;';
    report=NailSourceAnalysis.analyze(numericOperands,boot);
    eq(report.diagnostics[0].span.start,numericOperands.indexOf('missing'),
      'numeric overload traces the first operand of a lowered call');

    var equalityOperands='nail 0.54 ; def bad = missing == missing ;';
    report=NailSourceAnalysis.analyze(equalityOperands,boot);
    eq(report.diagnostics[0].span.start,equalityOperands.indexOf('missing'),
      'equality traces the first operand of a lowered call');

    var failingElse='nail 0.54 ; def bad = if true then 1 else missing ;';
    report=NailSourceAnalysis.analyze(failingElse,boot);
    eq(report.diagnostics[0].span.start,failingElse.indexOf('missing'),
      'Nail expression path resolves If else child');

    var nested='nail 0.54 ; def bad x = if x then x else missing ;';
    report=NailSourceAnalysis.analyze(nested,boot);
    eq(report.diagnostics[0].span.start,nested.indexOf('missing'),
      'Nail expression path traverses lambda and conditional');

    var applied='nail 0.54 ; def id x = x ; def bad = id missing ;';
    report=NailSourceAnalysis.analyze(applied,boot);
    eq(report.diagnostics[0].span.start,applied.indexOf('missing'),
      'Nail expression path traverses application argument');

    var duplicated='nail 0.54 ; def twice x = x ; def twice y = y ;';
    report=NailSourceAnalysis.analyze(duplicated,boot);
    eq(report.ok,false,'duplicate definition is rejected');
    eq(report.diagnostics[0].span.start,duplicated.lastIndexOf('twice'),
      'second declaration is the failing source location');

    report=NailSourceAnalysis.analyze(
      'nail 0.54 ; def wrong = 1 + true ;',boot);
    eq(report.ok,false,'numeric mismatch is rejected');
    eq(report.diagnostics[0].span,null,
      'unattributable inferred mismatch has no invented location');

    var partialSource='nail 0.54 ; type Option a = None | Some a ; '
      +'def partial = function | Some x -> x ;';
    report=NailSourceAnalysis.analyze(partialSource,boot);
    eq(report.ok,false,'incomplete match rejected by Nail');
    eq(report.diagnostics[0].span.start,partialSource.indexOf('function'),
      'unique original function-pattern site pinpointed');

    var macroSource='nail 0.54 ; type Option a = None | Some a ; '
      +'macro partial x = quote ( match unquote x with '
      +'| Some value -> value ) ;\n'
      +'expand partial ( Some 1 ) ;';
    report=NailSourceAnalysis.analyze(macroSource,boot);
    eq(report.ok,false,'incomplete macro-generated match rejected');
    eq(report.diagnostics[0].span.start,macroSource.indexOf('expand'),
      'macro-generated failure uses unique expansion site');
    eq(report.diagnostics[0].templateSpan.start,
      macroSource.indexOf('match'),'origin retained as related pattern location');

    var multiExpand=macroSource+'\nexpand partial ( Some 2 ) ;';
    report=NailSourceAnalysis.analyze(multiExpand,boot);
    eq(report.diagnostics[0].span.start,multiExpand.indexOf('expand'),
      'failing macro form chooses first invocation of two');
    eq(report.diagnostics[0].span.end,
      multiExpand.indexOf('expand')+'expand'.length,
      'macro site points to the expand keyword, not the complete call');

    var unrelated='nail 0.54 ; type Option a = None | Some a ; '
      +'def partial = function | Some x -> x ; '
      +'macro identity x = quote ( unquote x ) ; '
      +'expand identity ( Some 3 ) ;';
    report=NailSourceAnalysis.analyze(unrelated,boot);
    eq(report.diagnostics[0].span,null,
      'unrelated macro call is never blamed for a source match');
    eq(report.diagnostics[0].templateSpan,null,
      'unrelated macro template does not invent a source origin');

    // Macro provenance must identify the *specific invocation*, not the
    // first matching source token or a guessed globally unique expand call.
    var repeatedGenerated='nail 0.54 ; macro broken x = quote ( missing ) ; '
      +'def first = expand broken 1 ; def second = expand broken 2 ;';
    report=NailSourceAnalysis.analyze(repeatedGenerated,boot);
    eq(report.ok,false,'macro template unknown name rejected');
    eq(report.diagnostics[0].span.start,repeatedGenerated.indexOf('expand'),
      'first failing macro invocation is selected among two calls');
    eq(report.diagnostics[0].templateSpan.start,
      repeatedGenerated.indexOf('missing'),
      'generated unknown name retains its original template token');

    var generatedInBranches='nail 0.54 ; macro broken x = quote ( missing ) ; '
      +'def test = if true then expand broken 1 else expand broken 2 ;';
    report=NailSourceAnalysis.analyze(generatedInBranches,boot);
    eq(report.diagnostics[0].span.start,generatedInBranches.indexOf('expand'),
      'same-form repeated macro expansions distinguish the then branch');
    eq(report.diagnostics[0].templateSpan.start,
      generatedInBranches.indexOf('missing'),
      'same-form generated reference retains template origin');

    var holeSource='nail 0.54 ; macro identity x = quote ( unquote x ) ; '
      +'def test = expand identity missing ;';
    report=NailSourceAnalysis.analyze(holeSource,boot);
    eq(report.diagnostics[0].span.start,holeSource.indexOf('missing'),
      'unquoted caller argument retains its own location');
    eq(report.diagnostics[0].templateSpan,null,
      'unquoted caller argument is not falsely attributed to template');

    var secondMacro='nail 0.54 ; '
      +'macro identity x = quote ( unquote x ) ; '
      +'macro broken x = quote ( missing ) ; '
      +'def good = expand identity 1 ; '
      +'def bad = expand broken 2 ;';
    report=NailSourceAnalysis.analyze(secondMacro,boot);
    eq(report.diagnostics[0].span.start,secondMacro.lastIndexOf('expand'),
      'origin isolates second macro with other macro calls and prior forms');
    eq(report.diagnostics[0].templateSpan.start,secondMacro.indexOf('missing'),
      'template origin isolates second macro body');

    var nestedMacro='nail 0.54 ; '
      +'macro inner x = quote ( missing ) ; '
      +'macro outer x = quote ( expand inner ( unquote x ) ) ; '
      +'def broken = expand outer 1 ;';
    report=NailSourceAnalysis.analyze(nestedMacro,boot);
    eq(report.diagnostics[0].span.start,nestedMacro.lastIndexOf('expand'),
      'nested expansion retains outermost user-authored invocation');
    eq(report.diagnostics[0].templateSpan.start,nestedMacro.indexOf('missing'),
      'nested expansion retains inner macro template origin');

    var generatedNumeric='nail 0.54 ; '
      +'macro addOne x = quote ( unquote x + 1 ) ; '
      +'def good = expand addOne 2 ; '
      +'def bad = expand addOne true ;';
    report=NailSourceAnalysis.analyze(generatedNumeric,boot);
    eq(report.ok,false,'invalid generated numeric operator rejected');
    eq(report.diagnostics[0].span.start,generatedNumeric.lastIndexOf('expand'),
      'numeric error resolves to second macro invocation after a valid first');
    eq(report.diagnostics[0].templateSpan.start,generatedNumeric.indexOf('unquote x + 1'),
      'numeric error retains the quoted operator expression origin');

    var repeatedPattern='nail 0.54 ; type Option a = None | Some a ; '
      +'macro partial x = quote ( match unquote x with '
      +'| Some value -> value ) ; '
      +'def broken = if true then expand partial ( Some 1 ) '
      +'else expand partial ( Some 2 ) ;';
    report=NailSourceAnalysis.analyze(repeatedPattern,boot);
    eq(report.ok,false,'generated incomplete pattern in conditional rejected');
    eq(report.diagnostics[0].span.start,repeatedPattern.indexOf('expand'),
      'pattern failure selects first of two macro calls within one form');
    eq(report.diagnostics[0].templateSpan.start,repeatedPattern.indexOf('match'),
      'pattern failure retains exact quoted source pattern');

    // Imported macro diagnostics now own two separate source files. The
    // module's logical import key is the source identity of its template.
    var badModule='nail 0.54 ; macro broken x = quote ( missing ) ; export broken ;';
    var importedSource='nail 0.54 ; import broken from brokenLib ; '
      +'def first = expand broken 1 ; def second = expand broken 2 ;';
    var moduleReads=0;
    var importedResolver=(name:String) -> {
      if (name != 'brokenLib') return null;
      moduleReads++;
      return badModule;
    };
    report=NailSourceAnalysis.analyze(importedSource,boot,importedResolver,
      'src/main.nail');
    eq(report.ok,false,'imported macro type error rejected by Nail bytecode');
    eq(report.diagnostics[0].span.start,importedSource.indexOf('expand'),
      'imported macro selects first failing invocation in caller file');
    eq(report.diagnostics[0].templateSpan,null,
      'foreign macro span must not be mistaken for main source offset');
    eq(report.diagnostics[0].templateOrigin.sourceId,'brokenLib',
      'imported template uses logical module identity');
    eq(report.diagnostics[0].templateOrigin.span.start,
      badModule.indexOf('missing'),'foreign template offset is module-local');
    eq(moduleReads,1,'module source is fetched once across checking and provenance');

    var identityModule='nail 0.54 ; '
      +'macro identity x = quote ( unquote x ) ; export identity ;';
    var importedHole='nail 0.54 ; import identity from identityLib ; '
      +'def bad = expand identity missing ;';
    report=NailSourceAnalysis.analyze(importedHole,boot,
      name -> name == 'identityLib' ? identityModule : null);
    eq(report.ok,false,'bad caller argument still rejected through imported macro');
    eq(report.diagnostics[0].span.start,importedHole.indexOf('missing'),
      'unquote preserves source identity of importing caller');
    eq(report.diagnostics[0].templateOrigin,null,
      'unquoted caller node does not inherit imported template origin');

    var innerModule='nail 0.54 ; macro broken x = quote ( missing ) ; '
      +'export broken ;';
    var outerModule='nail 0.54 ; import broken from innerLib ; '
      +'macro wrapper x = quote ( expand broken ( unquote x ) ) ; '
      +'export wrapper ;';
    var nestedSource='nail 0.54 ; import wrapper from outerLib ; '
      +'def bad = expand wrapper 7 ;';
    var readsInner=0;
    var readsOuter=0;
    report=NailSourceAnalysis.analyze(nestedSource,boot,name -> {
      if (name == 'innerLib') { readsInner++; return innerModule; }
      if (name == 'outerLib') { readsOuter++; return outerModule; }
      return null;
    });
    eq(report.ok,false,'nested imported macro error rejected');
    eq(report.diagnostics[0].span.start,nestedSource.indexOf('expand'),
      'nested imported macro preserves outermost user call');
    eq(report.diagnostics[0].templateOrigin.sourceId,'innerLib',
      'nested imported macro reports actual producing module');
    eq(report.diagnostics[0].templateOrigin.span.start,
      innerModule.indexOf('missing'),'nested imported template points into inner source');
    eq(readsInner,1,'nested inner module loaded once per analysis');
    eq(readsOuter,1,'nested outer module loaded once per analysis');

    var successModule='nail 0.54 ; '
      +'macro identity x = quote ( unquote x ) ; export identity ;';
    var successImport='nail 0.54 ; import identity from utils ; '
      +'expand identity 42 ;';
    report=NailSourceAnalysis.analyze(successImport,boot,
      name -> name == 'utils' ? successModule : null);
    eq(report.ok,true,'Nail checker accepts valid imported expansion');
    eq(report.types,['Int'],'imported code receives Nail-inferred type');

    var missingModule='nail 0.54 ; import identity from nowhere ; '
      +'expand identity 1 ;';
    report=NailSourceAnalysis.analyze(missingModule,boot,
      name -> null);
    eq(report.ok,false,'missing module is reported rather than silently skipped');
    eq(report.diagnostics[0].span,null,
      'module resolver errors do not fabricate source coordinates');

    // Import-aware analysis must NOT erase Nail-only structural aliases,
    // parameter/value annotations or named-relation metadata. They pass
    // through Nail's own typed parser, the macro syntax bridge, and Nail's
    // typed metadata restoration before inference.
    var typedIdentity='nail 0.54 ; macro identity x = quote ( unquote x ) ; '
      +'export identity ;';
    var typedResolver=(name:String) -> name == 'typedHelpers'
      ? typedIdentity : null;

    var typedHtml='nail 0.54 ; '
      +'import identity from typedHelpers ; '
      +'type Html = { h2 : Text Text , div : Text Text } ; '
      +'def html = { h2 = fun x -> textConcat " H: " x , '
      +'div = fun x -> x } ; '
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'expand identity ( render html " Test " ) ;';
    report=NailSourceAnalysis.analyze(typedHtml,boot,typedResolver);
    eq(report.ok,true,'import preserves structural alias and context block');
    eq(report.types,['Text'],'import + context DSL infers Text in Nail');

    var typedParams='nail 0.54 ; import identity from typedHelpers ; '
      +'type Html = { h2 : Text Text , div : Text Text } ; '
      +'def render ( html : Html ) ( title : Text ) = html { h2 title } ; '
      +'expand identity ( render '
      +'{ h2 = fun x -> x , div = fun x -> x , extra = true } '
      +'" Typed " ) ;';
    report=NailSourceAnalysis.analyze(typedParams,boot,typedResolver);
    eq(report.ok,true,'import preserves multiple typed parameters');
    eq(report.types,['Text'],'multi-annotation source has Text evaluation');

    var typedValue='nail 0.54 ; import identity from typedHelpers ; '
      +'type Html = { h2 : Text Text , div : Text Text } ; '
      +'def html : Html = { h2 = fun x -> x , div = fun x -> x } ; '
      +'expand identity ( html . h2 " Value " ) ;';
    report=NailSourceAnalysis.analyze(typedValue,boot,typedResolver);
    eq(report.ok,true,'import preserves annotated top-level value declaration');
    eq(report.types,['Text'],'annotated value retains projection type');

    var constrained='nail 0.54 ; import identity from typedHelpers ; '
      +'Add : Int Int Int ; Add : Float Float Float ; '
      +'def add x y : Add = x + y ; '
      +'expand identity ( add 6 7 ) ; '
      +'expand identity ( add 1.25 0.5 ) ;';
    report=NailSourceAnalysis.analyze(constrained,boot,typedResolver);
    eq(report.ok,true,'import retains finite named relation signatures');
    eq(report.types,['Int','Float'],'named relation preserves overload choices');

    var rejectedRelation='nail 0.54 ; import identity from typedHelpers ; '
      +'Add : Int Int Int ; def add x y : Add = x + y ; '
      +'expand identity ( add 1.0 2.0 ) ;';
    report=NailSourceAnalysis.analyze(rejectedRelation,boot,typedResolver);
    eq(report.ok,false,'import must not erase relation restrictions');
    eq(report.diagnostics[0].message.indexOf('No relation instance') >= 0,
      true,'Nail rejects unsupported overload under imported macro');

    var rejectedField='nail 0.54 ; import identity from typedHelpers ; '
      +'type Html = { h2 : Text Text , div : Text Text } ; '
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'expand identity ( render { h2 = fun x -> x } " Missing " ) ;';
    report=NailSourceAnalysis.analyze(rejectedField,boot,typedResolver);
    eq(report.ok,false,'import must not erase structural alias contracts');
    eq(report.diagnostics[0].message.indexOf('Missing structural field') >= 0,
      true,'Nail checks the annotated DSL contract after import');

    // Supplying a module capability, even if unused, must not change the
    // behavior of ordinary annotated/DSL programs.
    var localOnly='nail 0.54 ; type Html = { h2 : Text Text } ; '
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'render { h2 = fun x -> x } " Local " ;';
    var localReport=NailSourceAnalysis.analyze(localOnly,boot);
    var moduleReport=NailSourceAnalysis.analyze(localOnly,boot,typedResolver);
    eq(moduleReport.ok,localReport.ok,
      'optional unused resolver does not change typed program acceptance');
    eq(moduleReport.types,localReport.types,
      'optional unused resolver does not change inferred types');

    trace('Nail-written typechecker core: '+checks+' differential checks passed');
  }
}
