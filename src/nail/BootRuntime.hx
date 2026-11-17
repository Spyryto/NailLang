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

  /** Grant a host resource reader to this source-free VM only. */
  @:keep
  public function grantTextReader(alias:String, capability:TextReadCapability):Void
    machine.grantTextReader(alias, capability);

  /** Opt-in discriminated Result[Text,Text] host read grant. */
  @:keep
  public function grantTextResultReader(alias:String, capability:TextReadCapability):Void
    machine.grantTextResultReader(alias, capability);

  /** Explicit write-only grant for the source-free bytecode runtime. */
  @:keep
  public function grantTextWriter(alias:String, capability:TextWriteCapability):Void
    machine.grantTextWriter(alias, capability);

  /** Compilation is performed by compileSource, a Nail function in bytecode. */
  @:keep
  public function compile(source:String, ?modules:String->Null<String>):Value return machine.compileSource(source, modules);

  /** Compile first-class Syntax with the Nail-written compiler only.
      No Haxe source parser is involved. */
  @:keep
  public function compileSyntax(tree:Value):Value
    return machine.compileSyntax(tree);

  /** Execute a program compiled by the bootstrapped Nail compiler. */
  @:keep
  public function run(source:String, ?modules:String->Null<String>):Array<Value> return machine.run(compile(source, modules));

  @:keep
  public function runPlain(source:String, ?modules:String->Null<String>):Array<Dynamic> return RuntimeValues.plainResults(run(source, modules));

  /** Invoke a transformer written in Nail after loading its definitions.
      Uses only compiled bytecode and the source-free runtime. */
  @:keep
  public function invoke(name:String, argument:Value):Value
    return machine.invoke(name, argument);

  /** Expose the lower-level structural API for inspection and subsequent stages. */
  @:keep
  public function runBytecode(program:Value):Array<Value> return machine.run(program);

  @:keep
  public function names():Array<String> return machine.names();
}

