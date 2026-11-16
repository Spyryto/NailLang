import haxe.Json;
import nail.Vm;
import nail.ByteVm;
import nail.TypeChecker;
import nail.BytecodeCompiler;

/** v0.18 algebraic variants: portable Haxe, JavaScript and PHP tests. */
class SumTestMain {
  static var passed = 0;
  static function check(value:Bool, message:String):Void {
    if (!value) throw 'SUM TEST FAILED: ' + message;
    passed++;
  }
  static function throwsLike(fn:Void->Void, expected:String):Void {
    var actual:Null<String> = null;
    try fn() catch (e:Dynamic) actual = Std.string(e);
    check(actual != null && actual.indexOf(expected) >= 0, 'expected ' + expected + ', got ' + actual);
  }
  static function result(source:String, expected:Dynamic):Void {
    var output = new Vm(10000000).runPlain(source);
    check(Json.stringify(output) == Json.stringify([expected]), 'AST VM: ' + source);
    var bytecode = BytecodeCompiler.compileSource(source);
    check(Json.stringify(new ByteVm(10000000).runPlain(bytecode)) == Json.stringify([expected]),
      'ByteVM: ' + source);
  }
  public static function main():Void {
    var option = 'type Option a = None | Some a ; ';
    var get = option + 'def fromOption x = match x with | None -> 0 | Some n -> n ; ';
    result(get + 'fromOption ( Some 8 ) ;', 8);
    result(get + 'fromOption None ;', 0);
    result(option + 'Some 3 == Some 3 ;', true);
    result(option + 'Some 3 != Some 4 ;', true);
    result(option + 'None == None ;', true);

    var response = 'type Result a e = Ok a | Error e ; ';
    var unwrap = response + 'def unwrap r = match r with | Error why -> 0 | Ok value -> value ; ';
    result(unwrap + 'unwrap ( Ok 16 ) ;', 16);
    result(unwrap + 'unwrap ( Error " failed " ) ;', 0);

    var tree = 'type Tree = Leaf Number | Branch Tree Tree ; ';
    var count = tree + 'def count t = match t with | Leaf n -> 1 | Branch a b -> count a + count b ; ';
    result(count + 'count ( Branch ( Leaf 2 ) ( Leaf 7 ) ) ;', 2);

    var t = new TypeChecker();
    t.check(option);
    check(t.signature('Some') == 'a -> Option[a]', 'Some signature');
    check(t.signature('None') == 'Option[a]', 'None signature');
    check(t.signature('Some.0') == 'Option[a] -> a', 'positional accessor signature');
    t.check('def get x = match x with | None -> 0 | Some n -> n ;');
    check(t.signature('get') == 'Option[Number] -> Number', 'match inference');
    check(Json.stringify(t.check('Some " hi " ; Some 5 ;')) ==
      '["Option[Text]","Option[Number]"]', 'constructor polymorphism');

    var r = new TypeChecker();
    r.check(response);
    check(r.signature('Ok') == 'a -> Result[a, b]', 'two-parameter generic result');
    throwsLike(() -> new TypeChecker().check('type Broken a = Unknown missing ;'), 'unknown');
    throwsLike(() -> new TypeChecker().check(option + 'Some true == Some 1 ;'), 'cannot unify');
    throwsLike(() -> new TypeChecker().check(option + 'type Other a = Some a ;'), 'duplicate');
    throwsLike(() -> new Vm().runPlain(option + 'match ( Some 1 ) with | None -> 0 ;'),
      'Non-exhaustive');
    trace('NailSeed v0.18 algebraic sums: ' + passed + ' tests passed');
  }
}
