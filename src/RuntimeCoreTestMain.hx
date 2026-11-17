import haxe.Json;
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
      vm.loadStdlib();
      var boot = new BootRuntime(60000000);
      ok(Json.stringify(vm.runPlain(source)) == Json.stringify(boot.runPlain(source)),
        'AST and source-free VM parity: ' + source);
    }

    var values:Array<Value> = [
      Number(42), Boolean(true), Text('hello'),
      Cons(Text('x'), Nil), record, leaf
    ];
    ok(Json.stringify(RuntimeValues.plainResults(values)) ==
       Json.stringify(Vm.plainResults(values)),
      'shared presentation agrees with development API');
    trace('Runtime core extraction: ' + checks + ' checks passed');
  }
}
