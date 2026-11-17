import haxe.Json;
import haxe.Resource;
import nail.BootRuntime;
import nail.Rebootstrap;

/** Same suite runs on Haxe --interp, generated Node.js, and generated PHP. */
class RebootstrapTestMain {
  static var count = 0;

  static function assertRun(image:String, source:String, expected:String):Void {
    var boot = new BootRuntime(30000000, image);
    var result = Json.stringify(boot.runPlain(source));
    if (result != expected) throw 'Boot runtime result mismatch: ' + source + ' : ' + result;
    count++;
  }

  static function main():Void {
    var seed = Resource.getString('bootstrap_image');
    var rawSource = Resource.getString('stdlib_source');
    if (seed == null || rawSource == null) throw 'Missing bootstrap test resources';
    var source = 'nail ' + numeric.LanguageVersion.CURRENT
      + ' ;\n' + rawSource;

    var second:String;
    #if (php && !full_rebootstrap)
    // The full PHP self-rebuild is available with -D full_rebootstrap, but is
    // too expensive to block every regular CI build. The normal PHP CI path
    // validates the exact Nail-built image and tests its compiler/runtime.
    second = Resource.getString('self_image');
    if (second == null) throw 'Missing self-regenerated bootstrap image';
    if (Rebootstrap.records(seed) != Rebootstrap.records(second))
      throw 'PHP image differs from Nail self-regenerated bootstrap image';
    count++;
    #else
    // This rebuild calls neither nail.Parser nor nail.BytecodeCompiler.
    var first = Rebootstrap.regenerate(seed, source);
    if (Rebootstrap.records(seed) != Rebootstrap.records(first))
      throw 'Stage-zero Haxe image and stage-one Nail image differ';
    count++;

    second = Rebootstrap.regenerate(first, source);
    if (Rebootstrap.records(first) != Rebootstrap.records(second))
      throw 'Nail stage-one and stage-two images differ';
    count++;
    #end

    if (Rebootstrap.fingerprint(seed) != Rebootstrap.fingerprint(second))
      throw 'Bootstrap image SHA-256 fingerprints differ';
    count++;

    // A runtime initialized using a self-regenerated image still parses,
    // compiles and executes user code without a Haxe source parser.
    assertRun(second, 'def square x = x * x ; square 9 ;', '[81]');
    assertRun(second, 'map ( fun x -> x + 3 ) [ 1 , 2 , 3 ] ;', '[[4,5,6]]');
    assertRun(second, 'match [ 8 , 4 ] with | [] -> 0 | h :: t -> h ;', '[8]');
    assertRun(second, 'def sum n acc = if n == 0 then acc else sum ( n - 1 ) ( acc + 1 ) ; sum 1500 0 ;', '[1500]');

    // Explicit canonical output is logged for cross-platform comparison.
    trace('NailSeed v0.15: ' + count + ' rebootstrap tests passed');
    trace('Bootstrap SHA256: ' + Rebootstrap.fingerprint(second));
  }
}
