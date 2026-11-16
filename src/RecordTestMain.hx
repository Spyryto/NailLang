import haxe.Json;
import nail.Vm;
import nail.ByteVm;
import nail.TypeChecker;
import nail.BytecodeCompiler;
import nail.BootstrapImage;
import nail.SyntaxEncoder;
import nail.SyntaxBridge;
import nail.Parser;
import nail.BootRuntime;

/** v0.17 nominal record regression suite. One codebase, three Haxe targets. */
class RecordTestMain {
  static var passed = 0;
  static function ok(condition:Bool, message:String):Void {
    if (!condition) throw 'RECORD TEST FAILED: ' + message;
    passed++;
  }
  static function throwsLike(run:Void->Void, phrase:String):Void {
    var message:Null<String> = null;
    try run() catch (e:Dynamic) message = Std.string(e);
    ok(message != null && message.indexOf(phrase) >= 0, 'wanted error ' + phrase + ', got ' + message);
  }
  static function expectResult(actual:Array<Dynamic>, property:String, expected:Dynamic):Void {
    ok(actual.length == 1 && Reflect.field(actual[0], property) == expected,
      'expected record field ' + property + ' = ' + Std.string(expected) + ', got ' + Json.stringify(actual));
  }
  public static function main():Void {
    var pfx = 'type Person { name Text age Number } ; ';
    var nested = pfx + 'type Badge { owner Person valid Bool } ; ';
    var a = pfx + 'def p = Person " Ada " 32 ; ';
    var vm = new Vm(15000000);
    expectResult(vm.runPlain(a + 'p ;'), 'name', 'Ada');
    ok(vm.runPlain('Person_name p ;')[0] == 'Ada', 'record name getter');
    ok(vm.runPlain('Person_age p ;')[0] == 32, 'record age getter');
    ok(vm.runPlain('p . name ;')[0] == 'Ada', 'dot name projection');
    ok(vm.runPlain('p . age + 1 ;')[0] == 33, 'dot precedence vs addition');
    ok(vm.runPlain('( Person " Bob " 20 ) . name ;')[0] == 'Bob', 'dot on constructed record');
    ok(vm.runPlain('Person_name ( Person " Bob " 20 ) ;')[0] == 'Bob', 'constructor application');
    ok(vm.runPlain('Person " Bob " 20 == Person " Bob " 20 ;')[0] == true, 'structural equality');
    ok(vm.runPlain('Person " Bob " 20 != Person " Bob " 21 ;')[0] == true, 'structural inequality');
    throwsLike(() -> vm.runPlain('Person_name 1 ;'), 'Expected record');
    var nv = new Vm(1000000);
    expectResult(nv.runPlain(nested + 'Badge ( Person " Ada " 32 ) true ;'), 'valid', true);
    ok(nv.runPlain('Person_age ( Badge_owner ( Badge ( Person " Ada " 32 ) false ) ) ;')[0] == 32,
      'nested nominal records');
    ok(nv.runPlain('( Badge ( Person " Ada " 32 ) false ) . owner . age ;')[0] == 32,
      'chained dot projection');
    throwsLike(() -> nv.runPlain('( Badge ( Person " Ada " 32 ) false ) . missing ;'), 'Unknown record field');
    throwsLike(() -> new Vm().run('type T { name Text } ; ( T " A " ) . ;'), 'Expected record field');
    throwsLike(() -> new Vm().run('type Empty { } ;'), 'Record requires');
    throwsLike(() -> new Vm().run('type Person { name Text name Number } ;'), 'Duplicate record field');
    throwsLike(() -> new Vm().run('type person { name Text } ;'), 'uppercase record type');
    throwsLike(() -> new Vm().run('type Person { name Text } ; type Person { age Number } ;'), 'Already defined');

    var typechecker = new TypeChecker();
    typechecker.check(pfx);
    ok(typechecker.signature('Person') == 'Text -> Number -> Person', 'constructor signature');
    ok(typechecker.signature('Person_name') == 'Person -> Text', 'name getter signature');
    ok(typechecker.signature('Person_age') == 'Person -> Number', 'age getter signature');
    ok(Json.stringify(typechecker.check('Person_name ( Person " Ada " 32 ) ;')) == '["Text"]', 'typed expression');
    ok(Json.stringify(typechecker.check('( Person " Ada " 32 ) . name ;')) == '["Text"]', 'typed dot expression');
    ok(Json.stringify(typechecker.check('( Person " Ada " 32 ) . age ;')) == '["Number"]', 'typed dot numeric field');
    typechecker.check('def ageOf person = person . age ;');
    ok(typechecker.signature('ageOf') == 'Person -> Number', 'unique field infers receiver type');
    throwsLike(() -> typechecker.check('( Person " Ada " 32 ) . missing ;'), 'has no field');
    throwsLike(() -> typechecker.check('42 . age ;'), 'expected record');
    throwsLike(() -> new TypeChecker().check(pfx + 'type Pet { name Text } ; def label x = x . name ;'), 'ambiguous record field');
    ok(Json.stringify(new TypeChecker().check(pfx + 'type Pet { name Text } ; ( Person " Ada " 32 ) . name ;')) == '["Text"]',
      'known receiver disambiguates shared field name');
    throwsLike(() -> typechecker.check('Person 3 4 ;'), 'cannot unify');
    throwsLike(() -> typechecker.check('Person_age " text " ;'), 'cannot unify');
    throwsLike(() -> new TypeChecker().check(pfx + 'type Pet { name Text age Number } ; Person_name ( Pet " Ada " 32 ) ;'), 'cannot unify');
    throwsLike(() -> new TypeChecker().check('type Bad { item Missing } ;'), 'unknown record field type');
    throwsLike(() -> new TypeChecker().check('type Bad { item Bad } ;'), 'unknown record field type');
    var alias = new TypeChecker();
    alias.check('type Alias { text String } ;');
    ok(alias.signature('Alias_text') == 'Alias -> Text', 'String alias');
    throwsLike(() -> new TypeChecker().check('type Bag { name Bool } ; type Bag_name { other Text } ;'), 'already defined');
    var t = new TypeChecker();
    throwsLike(() -> t.check('type Okay { name Text } ; type Bad { x Missing } ;'), 'unknown record field type');
    ok(t.names().indexOf('Okay') < 0, 'transactional type registration');
    t.check('type Good { name Text } ;');
    ok(t.signature('Good_name') == 'Good -> Text', 'retry after failed transaction');

    var src = pfx + 'def p = Person " Ada " 32 ; p . name ;';
    var reference = BytecodeCompiler.compileSource(src);
    var byteVm = new ByteVm(15000000);
    ok(Json.stringify(byteVm.runPlain(reference)) == '["Ada"]', 'bytecode compiler + ByteVm');
    var host = new Vm(15000000);
    host.loadStdlib();
    var tree = host.parseWithNail(src);
    var forms = SyntaxBridge.forms(tree);
    ok(forms.length == 3, 'Nail parser emits RecordType form');
    var compiled = host.compileWithNail(src);
    ok(BootstrapImage.encode(compiled) == BootstrapImage.encode(reference), 'bytecode identity between compilers');
    ok(Json.stringify(new ByteVm(15000000).runPlain(compiled)) == '["Ada"]', 'Nail-compiled record program');
    ok(Json.stringify(host.runPlainWithNail(src)) == '["Ada"]', 'self parsed record with AST VM');
    var checker = new TypeChecker();
    ok(Json.stringify(checker.checkSyntax(tree)) == '["Text"]', 'typed self-parser Syntax');
    ok(BootstrapImage.encode(BytecodeCompiler.compile(forms)) == BootstrapImage.encode(reference), 'SyntaxBridge roundtrip');
    ok(BootstrapImage.encode(BytecodeCompiler.compile(SyntaxBridge.forms(SyntaxEncoder.program(new Parser(src).parse())))) == BootstrapImage.encode(reference), 'SyntaxEncoder roundtrip');

    // The minimal source-free JS/PHP distribution must also accept the syntax.
    var boot = new BootRuntime(30000000);
    ok(Json.stringify(boot.runPlain(src)) == '["Ada"]', 'source-free bootstrap supports record syntax');
    var bootNested = new BootRuntime(30000000);
    ok(Json.stringify(bootNested.runPlain(nested + '( Badge ( Person " Ada " 32 ) true ) . owner . name ;')) == '["Ada"]',
      'source-free bootstrap supports chained dot');
    trace('NailSeed v0.17 record tests: ' + passed + ' passed');
  }
}
