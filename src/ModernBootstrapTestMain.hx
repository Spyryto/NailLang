import haxe.Resource;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.Rebootstrap;

/** Test migration of the complete Nail-written compiler/stdlib to Int,
    Ratio, Float, without altering production bootstrap until proven. */
class ModernBootstrapTestMain {
  static function main():Void {
    var old=Resource.getString('stdlib');
    if (old == null) throw 'Missing stdlib resource';
    var source='nail 0.46 ;\n'+old;
    var reference=BytecodeCompiler.compileSource(source);
    var seed=BootstrapImage.encode(reference);
    var runner=new BootRuntime(250000000,seed);
    var sample='nail 0.46 ; 1 / 3 + 1 / 6 ;';
    var output=runner.runPlain(sample);
    if (output.length != 1 || output[0] != 'R:1/2')
      throw 'Modern self-hosted bootstrap cannot execute exact arithmetic';
    // Recompile the entire stdlib using its own modern bytecode compiler,
    // then repeat with the newly built image. Both tapes must be identical
    // to the independent Haxe compiler.
    var regenerated=Rebootstrap.verify(seed, source, 250000000);
    if (Rebootstrap.records(regenerated)!=Rebootstrap.records(seed))
      throw 'Modern bootstrap is not a fixed point';
    trace('NailLang 0.46 modern bootstrap fixed point verified: '
      + Rebootstrap.fingerprint(regenerated));
  }
}
