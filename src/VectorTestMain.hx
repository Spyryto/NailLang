import haxe.Json;
import nail.BootRuntime;
import nail.BytecodeCompiler;
import nail.BootstrapImage;
import nail.TypeChecker;
import nail.Vm;

class VectorTestMain {
  static function check(ok:Bool, message:String):Void {
    if (!ok) throw message;
  }

  static function rejects(run:Void->Void, expected:String):Void {
    var message = '';
    try run() catch (e:Dynamic) message = Std.string(e);
    check(message.indexOf(expected) >= 0, 'Expected ' + expected + ', got ' + message);
  }

  static function main():Void {
    var source = 'def original = vector [ 10 , 20 , 30 ] ; '
      + 'def changed = vectorSet original 1 99 ; original ; changed ; '
      + 'vectorLength changed ; vectorGet changed 1 ; original == changed ; '
      + 'vector [] == vector [] ;';
    var expected = '[[10,20,30],[10,99,30],3,99,false,true]';
    var boot = new BootRuntime();
    var vm = new Vm(25000000);
    vm.loadStdlib();
    check(Json.stringify(vm.runPlain(source)) == expected, 'AST vector results');
    check(Json.stringify(boot.runPlain(source)) == expected, 'boot vector results');
    check(BootstrapImage.encode(vm.compileWithNail(source)) ==
      BootstrapImage.encode(BytecodeCompiler.compileSource(source)), 'vector bytecode parity');
    var types = new TypeChecker();
    check(Json.stringify(types.check(source)) ==
      '["Vector[Number]","Vector[Number]","Number","Number","Bool","Bool"]', 'vector types');
    check(types.signature('vectorGet') == 'Vector[a] -> Number -> a', 'vector polymorphism');
    rejects(() -> types.check('vectorSet original 1 true ;'), 'cannot unify');
    rejects(() -> types.check('head original ;'), 'cannot unify');
    rejects(() -> types.check('vector [ fun x -> x ] == vector [] ;'), 'functions cannot be compared');
    for (index in ['-1', '1.5', '2']) {
      rejects(() -> boot.run('vectorGet ( vector [ 10 , 20 ] ) ' + index + ' ;'), 'Vector index out of range');
      rejects(() -> vm.run('vectorSet ( vector [ 10 , 20 ] ) ' + index + ' 99 ;'), 'Vector index out of range');
    }
    trace('NailSeed vector tests passed');
  }
}
