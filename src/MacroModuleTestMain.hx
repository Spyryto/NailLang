import haxe.Json;
import haxe.ds.StringMap;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.TypeChecker;
import nail.Vm;

class MacroModuleTestMain {
  static function check(ok:Bool, message:String):Void {
    if (!ok) throw message;
  }

  static function rejects(run:Void->Void, expected:String):Void {
    var message = '';
    try run() catch (e:Dynamic) message = Std.string(e);
    check(message.indexOf(expected) >= 0, 'Expected ' + expected + ', got ' + message);
  }

  static function main():Void {
    var modules = new StringMap<String>();
    modules.set('arithmetic', 'macro add x = quote ( unquote x + 10 ) ; export add ;');
    modules.set('lesson', 'import add from arithmetic ; '
      + 'macro hidden x = quote ( let tmp = 10 in tmp + unquote x ) ; '
      + 'macro publicScore x = quote ( expand add ( expand hidden ( unquote x ) ) ) ; '
      + 'macro globalScore x = quote ( helper ( unquote x ) ) ; '
      + 'export publicScore ; export globalScore ;');
    var resolve = name -> modules.get(name);
    var source = 'import publicScore from lesson ; import globalScore from lesson ; '
      + 'def helper x = x + 10 ; let tmp = 22 in expand publicScore tmp ; '
      + 'let helper = false in expand globalScore 32 ;';
    var vm = new Vm(25000000);
    vm.loadStdlib();
    var boot = new BootRuntime();
    check(Json.stringify(vm.runPlain(source, resolve)) == '[42,42]', 'Host value mismatch');
    vm = new Vm(25000000);
    vm.loadStdlib();
    check(Json.stringify(vm.runPlainWithNail(source, resolve)) == '[42,42]', 'Nail value mismatch');
    var expected = BootstrapImage.encode(BytecodeCompiler.compileSource(source, resolve));
    check(expected == BootstrapImage.encode(vm.compileWithNail(source, resolve)), 'Compiler parity');
    check(expected == BootstrapImage.encode(boot.compile(source, resolve)), 'Bootstrap parity');
    check(Json.stringify(boot.runPlain(source, resolve)) == '[42,42]', 'Bootstrap values');
    check(Json.stringify(new TypeChecker().check(source, resolve)) == '["Number","Number"]', 'Host types');
    check(Json.stringify(new TypeChecker().checkSyntax(vm.parseWithNail(source, resolve))) ==
      '["Number","Number"]', 'Nail types');
    var reads = 0;
    boot.compile(source, name -> { if (name == 'lesson') reads++; return resolve(name); });
    check(reads == 1, 'Read a module once per compilation');
    check(boot.names().indexOf('publicScore') < 0, 'Macro leaked into runtime');
    modules.set('a', 'import b from b ; macro a = quote ( 1 ) ; export a ;');
    modules.set('b', 'import a from a ; macro b = quote ( 1 ) ; export b ;');
    modules.set('runtime', 'def notAllowed = 1 ; macro m = quote ( 1 ) ; export m ;');
    modules.set('reexport', 'import add from arithmetic ; export add ;');
    for (entry in [
      {code:'import hidden from lesson ;', error:'not exported'},
      {code:'import missing from missing ;', error:'missing macro module'},
      {code:'import a from a ;', error:'a -> b -> a'},
      {code:'import m from runtime ;', error:'only macro declarations'},
      {code:'import add from reexport ;', error:'export requires a local macro'},
      {code:'import add from arithmetic ; import add from arithmetic ;', error:'duplicate macro'},
      {code:'export unknown ;', error:'export is only allowed'},
      {code:'import publicScore from lesson ; expand publicScore true ;', error:'cannot unify'}
    ]) {
      rejects(() -> new TypeChecker().check(entry.code, resolve), entry.error);
      if (entry.error != 'cannot unify') rejects(() -> boot.run(entry.code, resolve), entry.error);
    }
    rejects(() -> boot.run('import publicScore from lesson ;'), 'requires a module resolver');
    check(Json.stringify(boot.runPlain('" import " ; " export " ; " from " ;')) ==
      '["import","export","from"]', 'Quoted keywords remain strings');
    trace('NailSeed macro module tests passed');
  }
}
