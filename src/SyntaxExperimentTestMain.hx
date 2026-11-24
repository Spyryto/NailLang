import haxe.Json;
import nail.Parser;
import nail.Vm;

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
    trace('Syntax experiment: '+count+' Haxe/JS/PHP checks passed');
  }
}
