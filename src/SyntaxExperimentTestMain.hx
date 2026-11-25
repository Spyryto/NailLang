import haxe.Json;
import nail.Parser;
import nail.Vm;
import nail.TypeChecker;

class SyntaxExperimentTestMain {
  static var count=0;
  static function assertTrue(value:Bool,label:String):Void {
    if (!value) throw 'SYNTAX EXPERIMENT: '+label;
    count++;
  }
  static function assertRun(body:String,expected:Array<Dynamic>,label:String):Void {
    var vm=new Vm(2000000);
    var actual=vm.runPlainExperimental('nail 0.61 ; '+body);
    assertTrue(Json.stringify(actual)==Json.stringify(expected),
      label+': expected '+Json.stringify(expected)+', received '+Json.stringify(actual));
  }
  static function assertError(body:String,fragment:String,label:String):Void {
    var error='';
    try new Vm().runPlainExperimental('nail 0.61 ; '+body)
    catch (e:Dynamic) error=Std.string(e);
    assertTrue(error.indexOf(fragment)>=0,
      label+': wanted '+fragment+', got '+error);
  }
  static function standardRejects(body:String,label:String):Void {
    var failed=false;
    try new Parser('nail 0.61 ; '+body).parse()
    catch (_:Dynamic) failed=true;
    assertTrue(failed,label+' must remain opt-in');
  }
  static function assertTypes(body:String,expected:Array<String>,label:String):Void {
    var actual=new TypeChecker().checkExperimental('nail 0.61 ; '+body);
    assertTrue(Json.stringify(actual)==Json.stringify(expected),
      label+': expected '+Json.stringify(expected)+', received '+Json.stringify(actual));
  }
  static function assertTypeError(body:String,fragment:String,label:String):Void {
    var error='';
    try new TypeChecker().checkExperimental('nail 0.61 ; '+body)
    catch (e:Dynamic) error=Std.string(e);
    assertTrue(error.indexOf(fragment)>=0,label+': wanted '+fragment+', got '+error);
  }
  public static function main():Void {
    var pair='def pair first second = first * 10 + second ; ';
    assertRun('def map-empty = 42 ; map-empty ;',['I:42/1'],
      'hyphenated identifiers');
    assertRun('def add-one x = x + 1 ; 41 >> add-one ;',['I:42/1'],
      'hyphenated functions with pipe');
    assertRun('def less x y = x - y ; less 50 8 ;',['I:42/1'],
      'minus operator still works when separated by spaces');
    assertRun(pair+'pair 4 2 ;',['I:42/1'],'original positional call');
    assertRun(pair+'pair first: 4 second: 2 ;',['I:42/1'],
      'named arguments in declaration order');
    assertRun(pair+'pair second: 2 first: 4 ;',['I:42/1'],
      'named arguments in reverse order');
    assertRun(pair+'pair 4 second: 2 ;',['I:42/1'],
      'mixed: positional then named');
    assertRun(pair+'pair first: 4 2 ;',['I:42/1'],
      'mixed: named then positional');
    assertRun(pair+'pair second: 2 4 ;',['I:42/1'],
      'mixed: named then fill first missing');
    assertRun(pair+'def plusTwo = pair second: 2 ; plusTwo 4 ;',
      ['I:42/1'],'partial application by second name');
    assertRun(pair+'def plusForty = pair first: 4 ; plusForty 2 ;',
      ['I:42/1'],'partial application by first name');
    assertRun(pair+'4 >> pair second: 2 ;',['I:42/1'],
      'named partial call through pipe');
    assertRun('def double x = x + x ; 1 + 2 >> double ;',
      ['I:6/1'],'pipe lower precedence than arithmetic');
    assertRun('def double x = x + x ; def identity x = x ; '
      +'21 >> double >> identity ;',['I:42/1'],
      'pipe is left associative');
    assertRun('def identity x = x ; identity " hello-world " ;',
      ['hello-world'],'hyphen inside a string unaffected');
    assertRun('def set-delete entries item = item ; '
      +'set-delete entries: [ 1 , 2 , 3 ] item: 2 ;',
      ['I:2/1'],'named call with list literal');
    assertRun(pair+'def applyToFour f = f 4 ; '
      +'pair second: 2 >> applyToFour ;',
      ['I:42/1'],'higher-order partial calls remain functions');
    assertError(pair+'pair third: 3 ;','Unknown named parameter',
      'unknown parameter rejected');
    assertError(pair+'pair first: 4 first: 4 ;','Duplicate argument',
      'duplicate parameter rejected');
    assertError(pair+'pair 4 first: 4 ;','Duplicate argument',
      'positional/named duplication rejected');
    assertError('missing value: 4 ;','local definition',
      'unknown function cannot be guessed from label');
    standardRejects('def add-one x = x + 1 ;','hyphen name');
    standardRejects('def id x = x ; 2 >> id ;','pipe operator');
    standardRejects(pair+'pair first: 4 second: 2 ;','named calls');
    var fraction='def fraction numerator: a denominator: b = a / b ; ';
    assertRun(fraction+'fraction 3 2 ;',['R:3/2'],
      'renamed parameters still support positional calls');
    assertRun(fraction+'fraction numerator: 3 denominator: 2 ;',['R:3/2'],
      'public labels are independent of local binders');
    assertRun(fraction+'fraction denominator: 2 numerator: 3 ;',['R:3/2'],
      'renamed labels in reverse order');
    assertRun(fraction+'fraction 3 denominator: 2 ;',['R:3/2'],
      'renamed labels mixed with positional arguments');
    assertRun(fraction+'def half = fraction denominator: 2 ; half 3 ;',['R:3/2'],
      'renamed label supports non-prefix partial application');
    assertRun(fraction+'3 >> fraction denominator: 2 ;',['R:3/2'],
      'renamed partial application through pipeline');
    assertRun('def combine left: b a = b * 10 + a ; combine a: 2 left: 4 ;',
      ['I:42/1'],'explicit and implicit labels can coexist');
    assertRun('def pair first: second second: first = second * 10 + first ; '
      +'pair first: 4 second: 2 ;',['I:42/1'],
      'public labels and local binders occupy separate namespaces');
    assertError(fraction+'fraction a: 3 ;','Unknown named parameter',
      'local binder is not a public alias');
    assertError('def bad same: a same: b = a ;','Duplicate public parameter label',
      'duplicate public labels rejected');
    assertError('def bad first: a second: a = a ;','Invalid or duplicate definition parameter',
      'duplicate local binders rejected');
    assertError('def bad first: a first = a ;','Duplicate public parameter label',
      'explicit label colliding with an implicit label rejected');
    standardRejects(fraction,'renamed definition parameters');
    var typedFraction='def fraction numerator: ( a : Int ) denominator: ( b : Int ) = a / b ; ';
    assertTypes(typedFraction+'fraction 3 2 ; fraction denominator: 2 numerator: 3 ;',
      ['Ratio','Ratio'],'typed positional and reordered labelled calls');
    assertTypes(typedFraction+'def half = fraction denominator: 2 ; half 3 ;',
      ['Ratio'],'typed partial application of renamed parameter');
    assertTypes(typedFraction+'3 >> fraction denominator: 2 ;',
      ['Ratio'],'pipeline retains inferred result');
    var checker=new TypeChecker();
    checker.checkExperimental('nail 0.61 ; '+typedFraction+'def half = fraction denominator: 2 ;');
    assertTrue(checker.signature('half')=='Int -> Ratio','partial function has expected signature');
    assertTypeError(typedFraction+'fraction numerator: " bad " denominator: 2 ;',
      'cannot unify','wrong type is rejected under the correct label');
    assertTypeError(typedFraction+'def half = fraction denominator: 2 ; half " bad " ;',
      'cannot unify','partial application retains its input constraint');
    var choose='def choose first: a second: b = a ; ';
    assertTypes(choose+'choose second: true first: 42 ; choose first: " hello " second: 2 ;',
      ['Int','Text'],'polymorphic function remains polymorphic');
    assertTypes(choose+'def keep = choose second: true ; keep 42 ; keep " hello " ;',
      ['Int','Text'],'polymorphic named partial application');
    assertTypes('def get-name data = data . name ; get-name data: { name = " Nail " } ;',
      ['Text'],'structural record inference with hyphenated name and label');
    assertTypeError(choose+'def wrapper choose = choose second: true ;',
      'shadowed function','definition parameter hides global labels');
    assertError(choose+'( fun choose -> choose second: true ) ( fun a -> a ) ;',
      'shadowed function','lambda parameter hides global labels at runtime');
    assertError(choose+'let choose = ( fun x -> x ) in choose second: true ;',
      'shadowed function','let binder hides global labels');
    assertTypes(choose+'let choose = ( fun x -> x ) in choose 42 ;',
      ['Int'],'ordinary positional call to shadowed local is valid');
    assertTypes(choose+'( fun choose -> choose 42 ) ( fun x -> x ) ;',
      ['Int'],'ordinary lambda shadowing stays valid');
    assertTypes(choose+'( let choose = ( fun x -> x ) in choose 42 ) ; choose first: 42 second: true ;',
      ['Int','Int'],'outer labels restored after leaving scope');
    var standardError=false;
    try new TypeChecker().check('nail 0.61 ; '+typedFraction)
    catch (_:Dynamic) standardError=true;
    assertTrue(standardError,'ordinary type checker keeps syntax opt-in');
    var sample='nail 0.61 ;\n'+typedFraction+'\ndef half = fraction denominator: 2 ;\nhalf 3 ;';
    var report=Main.analyzeExperimental(sample);
    assertTrue(report.ok && report.evaluations[0].type=='Ratio',
      'experimental analysis exposes result type');
    var halfSignature='';
    for (symbol in report.symbols) if (symbol.name=='half') halfSignature=symbol.signature;
    assertTrue(halfSignature=='Int -> Ratio','experimental analysis exposes signature');
    var wrong=Main.analyzeExperimental(sample+'\nhalf " bad " ;');
    assertTrue(!wrong.ok && wrong.diagnostics[0].phase=='type'
      && wrong.diagnostics[0].span!=null && wrong.diagnostics[0].span.line==5,
      'experimental analysis retains type error form location');
    assertTrue(!Main.analyze(sample).ok,'ordinary analysis rejects experimental source');
    var view=Main.expandExperimental(sample);
    assertTrue(view.indexOf('fun a ->')>=0 && view.indexOf('#exp_')>=0,
      'expanded view exposes ordinary lambdas and captures');
    var summ='def summ x y = x + y ; ';
    assertTypes(summ+'summ 15 3 ; summ 1.5 2.5 ; summ ( 1 / 2 ) 3 ;',
      ['Int','Float','Ratio'],'inferred arithmetic constraints specialize independently');
    assertTypes(summ+'def add-three = summ y: 3 ; add-three 10 ; add-three ( 1 / 2 ) ;',
      ['Int','Ratio'],'numeric constraints survive named partial application');
    assertTypes(summ+'def add-three = summ 3 ; add-three 10 ;',
      ['Int'],'numeric constraints survive positional partial application');
    assertTypes(summ+'def apply f x = f x ; apply ( summ y: 3 ) 10 ;',
      ['Int'],'numeric constraints through higher-order application');
    assertTypes(summ+'def twice x = summ x x ; twice 2 ; twice 1.5 ;',
      ['Int','Float'],'repeated type variables in relation rows');
    assertTypes('def f x = let y = x + 1 in y + 2 ; f 3 ;',
      ['Int'],'local binding preserves constraints on captured parameter');
    assertTypes('def fraction numerator: a denominator: b = a / b ; '
      +'def half = fraction denominator: 2 ; half 3 ;',
      ['Ratio'],'unannotated renamed fraction');
    assertTypeError(summ+'summ " bad " 3 ;','no Add instance','Text is not numeric');
    assertTypeError(summ+'summ 1.5 3 ;','no Add instance','mixed Float and Int rejected');
    assertTypeError(summ+'def add-three = summ y: 3 ; add-three true ;',
      'no Add instance','partial application cannot erase numeric constraint');
    var numericChecker=new TypeChecker();
    numericChecker.checkExperimental('nail 0.61 ; '+summ+'def add-three = summ y: 3 ;');
    assertTrue(numericChecker.signature('summ')=='Add a b c => a -> b -> c',
      'qualified inferred signature');
    assertTrue(numericChecker.signature('add-three').indexOf('Add')>=0,
      'qualified partial signature');
    assertTrue(numericChecker.checkExperimental('nail 0.61 ; summ 4 5 ;')[0]=='Int',
      'predicates survive a new checker session');
    var exportRejected=false;
    try numericChecker.publicScheme('summ') catch (_:Dynamic) exportRejected=true;
    assertTrue(exportRejected,'public ABI cannot silently discard numeric constraints');
    var oldRejected=false;
    try new TypeChecker().check('nail 0.61 ; '+summ) catch (_:Dynamic) oldRejected=true;
    assertTrue(oldRejected,'stable inference is unchanged');
    var ordered='nail 0.61 ; def pair a b = a ; ';
    var positionalView=Main.expandExperimental(ordered+'pair 1 2 ;');
    assertTrue(Main.expandExperimental(ordered+'pair a: 1 b: 2 ;')==positionalView,
      'saturated named call in order has the same core as positional');
    assertTrue(Main.expandExperimental(ordered+'pair 1 b: 2 ;')==positionalView,
      'saturated mixed call in order has the same core');
    assertTrue(Main.expandExperimental(ordered+'pair b: 2 a: 1 ;').indexOf('#exp_')>=0,
      'reordered calls retain evaluation captures');
    assertTrue(Main.expandExperimental(ordered+'def later = pair b: 2 ;').indexOf('#exp_')>=0,
      'non-prefix partial calls retain captures');
    var session=new Vm();
    session.runExperimental('nail 0.61 ; '+fraction);
    assertTrue(Json.stringify(session.runPlainExperimental('nail 0.61 ; fraction denominator: 2 numerator: 3 ;'))==Json.stringify(['R:3/2']),
      'runtime remembers declaration labels across source units');
    assertTrue(Json.stringify(session.runPlainExperimental('nail 0.61 ; def half = fraction denominator: 2 ; half 3 ;'))==Json.stringify(['R:3/2']),
      'partial application across separate source units');
    var sessionTypes=new TypeChecker();
    sessionTypes.checkExperimental('nail 0.61 ; '+fraction);
    assertTrue(sessionTypes.checkExperimental('nail 0.61 ; fraction numerator: 3 denominator: 2 ;')[0]=='Ratio',
      'checker remembers declaration labels and inferred predicates');
    var copied=sessionTypes.copy();
    assertTrue(copied.checkExperimental('nail 0.61 ; fraction denominator: 2 numerator: 3 ;')[0]=='Ratio',
      'checker copy preserves labels');
    var rejected=false;
    try sessionTypes.checkExperimental('nail 0.61 ; def bad alias: a = a + true ;')
    catch (_:Dynamic) rejected=true;
    assertTrue(rejected,'failed static definition rejected');
    var leaked=false;
    try sessionTypes.checkExperimental('nail 0.61 ; bad alias: 3 ;')
    catch (e:Dynamic) leaked=Std.string(e).indexOf('local definition')>=0;
    assertTrue(leaked,'failed static definition publishes no labels');
    trace('Syntax experiment: '+count+' Haxe/JS/PHP checks passed');
  }
}
