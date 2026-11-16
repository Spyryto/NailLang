package nail;

import haxe.Resource;
import nail.Value;

/** Source-free runtime bootstrap.
    The standard library is already compiled before packaging JS/PHP.
    No Haxe parser is called to load it, parse user code or compile user code. */
@:keep
class BootRuntime {
  final machine:ByteVm;

  public function new(maxSteps:Int = 25000000, ?image:String) {
    machine = new ByteVm(maxSteps);
    var encoded = image == null ? Resource.getString('bootstrap_image') : image;
    if (encoded == null) throw 'Missing bootstrap bytecode image';
    machine.run(BootstrapImage.decode(encoded));
  }

  /** Compilation is performed by compileSource, a Nail function in bytecode. */
  @:keep
  public function compile(source:String):Value return machine.compileSource(source);

  /** Execute a program compiled by the bootstrapped Nail compiler. */
  @:keep
  public function run(source:String):Array<Value> return machine.run(compile(source));

  @:keep
  public function runPlain(source:String):Array<Dynamic> return Vm.plainResults(run(source));

  /** Expose the lower-level structural API for inspection and subsequent stages. */
  @:keep
  public function runBytecode(program:Value):Array<Value> return machine.run(program);

  @:keep
  public function names():Array<String> return machine.names();
}
