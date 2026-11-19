import haxe.Json;
import haxe.Timer;
import nail.Value;
import nail.RuntimePrimitives;
import nail.RuntimeValues;
import nail.Vm;
import nail.BootRuntime;
import numeric.FastNumber;

/** Regression: both VM front ends use one independent native core.
    Run the same cases on Haxe, JavaScript, and PHP. */
class RuntimeCoreTestMain {
  static var checks = 0;
  static var bootInstances = 0;
  static var bootSeconds = 0.0;
  static var hostStdlibSeconds = 0.0;
  static var hostRunSeconds = 0.0;
  static var bootRunSeconds = 0.0;

  static function freshBoot(steps:Int):BootRuntime {
    var start = Timer.stamp();
    var boot = new BootRuntime(steps);
    bootSeconds += Timer.stamp() - start;
    bootInstances++;
    return boot;
  }


  static function ok(good:Bool, label:String):Void {
    if (!good) throw 'RUNTIME CORE: ' + label;
    checks++;
  }

  static function textValue(value:Value):String return switch value {
    case Text(text): text;
    case _: throw 'Expected Text result';
  };

  static function checkPlain(value:Value, expected:Dynamic, label:String):Void {
    var actual = RuntimeValues.toPlain(value);
    ok(Json.stringify(actual) == Json.stringify(expected),
      label + ' expected ' + Json.stringify(expected)
      + ', got ' + Json.stringify(actual));
  }

  public static function main():Void {
    var first = RuntimePrimitives.environment();
    var second = RuntimePrimitives.environment();
    ok(switch first.lookup('+') {
      case Native('+', 2, _): true;
      case _: false;
    }, 'native registration and arity');
    first.bind('isolation', Boolean(true));
    ok(!second.hasHere('isolation'), 'runtime environments do not share caller bindings');

    checkPlain(RuntimePrimitives.apply('+', [Number(20), Number(22)]),
      42, 'approximate arithmetic');
    checkPlain(RuntimePrimitives.apply('#modern+', [
      IntNumber(FastNumber.exact('20')),
      IntNumber(FastNumber.exact('22'))]), 'I:42/1', 'modern exact Int arithmetic');
    checkPlain(RuntimePrimitives.apply('#modern/', [
      IntNumber(FastNumber.exact('1')),
      IntNumber(FastNumber.exact('2'))]), 'R:1/2', 'modern Ratio division');
    checkPlain(RuntimePrimitives.apply('textConcat', [Text('ab'), Text('cd')]),
      'abcd', 'text primitive');

    var list = Cons(Text('first'), Cons(Text('second'), Nil));
    checkPlain(RuntimePrimitives.apply('head', [list]),
      'first', 'list head');
    checkPlain(RuntimePrimitives.apply('tail', [list]),
      ['second'], 'list tail');
    checkPlain(RuntimePrimitives.apply('vectorGet', [
      Vector([Number(10), Number(42)]), Number(1)]),
      42, 'vector primitive');

    var record = RuntimePrimitives.apply('#recordMake', [
      Text('Box'), Cons(Text('value'), Nil),
      Cons(IntNumber(FastNumber.exact('42')), Nil)]);
    checkPlain(RuntimePrimitives.apply('#recordGet', [record, Text('value')]),
      'I:42/1', 'record construction and projection');
    var leaf = RuntimePrimitives.apply('syntaxLeaf',
      [Text('Name'), Text('answer')]);
    checkPlain(RuntimePrimitives.apply('syntaxTag', [leaf]),
      'Name', 'Syntax primitive');

    var sources = [
      'nail 0.49 ; 1 / 3 + 1 / 6 ;',
      'nail 0.49 ; type Box { value Int } ; ( Box 42 ) . value ;',
      'nail 0.49 ; type Choice = No | Yes Int ; match Yes 42 with | No -> 0 | Yes n -> n ;',
      'nail 0.49 ; macro twice x = quote ( unquote x + unquote x ) ; expand twice 21 ;'
    ];
    for (source in sources) {
      var vm = new Vm(60000000);
      var start = Timer.stamp();
      vm.loadStdlib();
      hostStdlibSeconds += Timer.stamp() - start;
      var boot = freshBoot(60000000);
      start = Timer.stamp();
      var hostResult = vm.runPlain(source);
      hostRunSeconds += Timer.stamp() - start;
      start = Timer.stamp();
      var bootResult = boot.runPlain(source);
      bootRunSeconds += Timer.stamp() - start;
      ok(Json.stringify(hostResult) == Json.stringify(bootResult),
        'AST and source-free VM parity: ' + source);
    }

    var values:Array<Value> = [
      Number(42), Boolean(true), Text('hello'),
      Cons(Text('x'), Nil), record, leaf
    ];
    ok(Json.stringify(RuntimeValues.plainResults(values)) ==
       Json.stringify(Vm.plainResults(values)),
      'shared presentation agrees with development API');
    trace('CI profile runtime/BootRuntime init: count=' + bootInstances
      + ', total_ms=' + Math.round(bootSeconds * 1000));
    trace('CI profile runtime/Vm stdlib load: count=' + bootInstances
      + ', total_ms=' + Math.round(hostStdlibSeconds * 1000));
    trace('CI profile runtime/Vm execute: count=' + bootInstances
      + ', total_ms=' + Math.round(hostRunSeconds * 1000));
    trace('CI profile runtime/BootRuntime compile-and-execute: count=' + bootInstances
      + ', total_ms=' + Math.round(bootRunSeconds * 1000));
    trace('Runtime core extraction: ' + checks + ' checks passed');
  }
}
