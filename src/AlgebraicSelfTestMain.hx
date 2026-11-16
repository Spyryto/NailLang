import haxe.Json;
import nail.Vm;
import nail.ByteVm;
import nail.TypeChecker;
import nail.BytecodeCompiler;
import nail.BootstrapImage;
import nail.SyntaxBridge;
import nail.SyntaxEncoder;
import nail.Parser;
import nail.BootRuntime;

/** v0.19 cross-compiler ADT agreement + static constructor coverage. */
class AlgebraicSelfTestMain {
  static var passed:Int = 0;

  static function check(condition:Bool, detail:String):Void {
    if (!condition) throw 'ALGEBRAIC SELF TEST FAILED: ' + detail;
    passed++;
  }
  static function expectError(test:Void->Void, phrase:String):Void {
    var message:Null<String> = null;
    try test() catch (e:Dynamic) message = Std.string(e);
    check(message != null && message.toLowerCase().indexOf(phrase.toLowerCase()) >= 0,
      'expected error ' + phrase + ', got ' + message);
  }
  static function equalOutput(actual:Array<Dynamic>, expected:Dynamic, description:String):Void {
    check(Json.stringify(actual) == Json.stringify([expected]),
      description + ' expected ' + Json.stringify(expected) + ', got ' + Json.stringify(actual));
  }

  static function checkSelf(source:String, expected:Dynamic, description:String):Void {
    var expectedCode = BytecodeCompiler.compileSource(source);
    var vm = new Vm(30000000);
    vm.loadStdlib();
    var parsed = vm.parseWithNail(source);
    var form = SyntaxBridge.forms(parsed);
    check(BootstrapImage.encode(SyntaxEncoder.program(form)) ==
      BootstrapImage.encode(SyntaxEncoder.program(new Parser(source).parse())),
      description + ': parser syntax equivalence');
    var actualCode = vm.compileWithNail(source);
    check(BootstrapImage.encode(actualCode) == BootstrapImage.encode(expectedCode),
      description + ': full bytecode identity');
    equalOutput(new ByteVm(30000000).runPlain(actualCode), expected,
      description + ': Nail compiled ByteVM result');
    equalOutput(vm.runPlainWithNail(source), expected,
      description + ': Nail self-parser + AST VM');
    equalOutput(new BootRuntime(40000000).runPlain(source), expected,
      description + ': precompiled source-free bootstrap');
    var checker = new TypeChecker();
    check(Json.stringify(checker.checkSyntax(parsed)) == '["Number"]',
      description + ': self Syntax typed as Number');
  }

  static function main():Void {
    var option = 'type Option a = None | Some a ; ';
    var result = 'type Result a e = Ok a | Error e ; ';
    var duo = 'type Duo = Both Number Number | Neither ; ';
    var classify = 'def classify opt = match opt with | None -> 0 | Some x -> x ; ';

    checkSelf(option + classify + 'classify ( Some 9 ) ;', 9, 'generic Option');
    checkSelf(result + 'def resultOrZero r = match r with | Ok n -> n | Error why -> 0 ; '
      + 'resultOrZero ( Ok 11 ) ;', 11, 'two-parameter Result');
    checkSelf(duo + 'def total pair = match pair with | Both x y -> x + y | Neither -> 0 ; '
      + 'total ( Both 7 5 ) ;', 12, 'two-field constructor');

    var checker = new TypeChecker();
    checker.check(option);
    check(checker.signature('Some') == 'a -> Option[a]', 'polymorphic constructor signature');
    check(Json.stringify(checker.check(classify + 'classify ( Some 8 ) ;')) == '["Number"]',
      'full match checks and infers');
    expectError(() -> new TypeChecker().check(option +
      'match ( Some 1 ) with | Some x -> x ;'), 'non-exhaustive');
    expectError(() -> new TypeChecker().check(option +
      'match None with | None -> 0 ;'), 'missing Some');
    expectError(() -> new TypeChecker().check(option +
      'match ( Some 1 ) with | Some -> 2 | None -> 0 ;'), 'expects 1 match bindings');
    expectError(() -> new TypeChecker().check(option +
      'match ( Some 1 ) with | Some x y -> x | None -> 0 ;'), 'expects 1 match bindings');
    expectError(() -> new TypeChecker().check(option + result +
      'match ( Some 1 ) with | Some n -> n | Error e -> 0 | None -> 0 ;'),
      'mixed constructors');
    expectError(() -> new TypeChecker().check(option +
      'match ( Some 1 ) with | Some x -> x | Some n -> n | None -> 0 ;'), 'duplicate');

    // Nested case analysis must be visited recursively, even inside a branch body.
    expectError(() -> new TypeChecker().check(option +
      'def nested o = match o with | None -> 0 | Some x -> '
      + '( match o with | Some y -> y ) ;'), 'non-exhaustive');

    // The declaration registry is transactional and persists across successful check() calls.
    var state = new TypeChecker();
    expectError(() -> state.check(option + 'match None with | None -> 0 ;'), 'non-exhaustive');
    check(state.names().indexOf('Some') < 0, 'failed check does not commit ADT registry');
    state.check(option);
    check(Json.stringify(state.check('match ( Some 5 ) with | Some n -> n | None -> 0 ;'))
      == '["Number"]', 'ADT registry persists across successful checks');

    // Test both parser boundaries for malformed and complete matches.
    var host = new Vm(30000000);
    host.loadStdlib();
    var malformed = option + 'match ( Some 1 ) with | Some x -> x ;';
    expectError(() -> new TypeChecker().checkSyntax(host.parseWithNail(malformed)), 'non-exhaustive');
    var valid = option + 'match ( Some 2 ) with | Some x -> x | None -> 0 ;';
    check(Json.stringify(new TypeChecker().checkSyntax(host.parseWithNail(valid))) == '["Number"]',
      'self parser works with ADT coverage validation');

    trace('NailSeed v0.19 algebraic self tests: ' + passed + ' passed');
  }
}
