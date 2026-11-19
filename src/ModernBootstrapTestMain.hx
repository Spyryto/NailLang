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
    var source='nail '+numeric.LanguageVersion.CURRENT+' ;\n'+old;
    var reference=BytecodeCompiler.compileSource(source);
    var seed=BootstrapImage.encodeModern(reference);
    var official=Resource.getString('bootstrap_image');
    if (official == null || !BootstrapImage.isModernImage(official))
      throw 'Official build bootstrap is not a modern v2 image';
    if (Rebootstrap.records(seed) != Rebootstrap.records(official))
      throw 'Official bootstrap differs from independent Haxe modern image';
    var runner=new BootRuntime(250000000,official);
    var sample='nail '+numeric.LanguageVersion.CURRENT+' ; 1 / 3 + 1 / 6 ;';
    var output=runner.runPlain(sample);
    if (output.length != 1 || output[0] != 'R:1/2')
      throw 'Modern self-hosted bootstrap cannot execute exact arithmetic';
    // Recompile the entire stdlib using its own modern bytecode compiler,
    // then repeat with the newly built image. Both tapes must be identical
    // to the independent Haxe compiler.
    // Permit the growing self-hosted stdlib a finite rebuild budget;
    // identical bytecode across all stages is still mandatory.
    var regenerated=Rebootstrap.verify(official, source, 500000000);
    if (Rebootstrap.records(regenerated)!=Rebootstrap.records(official))
      throw 'Modern bootstrap is not a fixed point';
    trace('NailLang 0.47 official modern bootstrap fixed point verified: '
      + Rebootstrap.fingerprint(regenerated));
  }
}
