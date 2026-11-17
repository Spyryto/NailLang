import haxe.Resource;
import sys.FileSystem;
import sys.io.File;
import nail.Rebootstrap;

/** CLI stage-one + stage-two generator; both stages compile with Nail bytecode.
    The stage-zero image is supplied as a Haxe resource from the build step. */
class RebootstrapImageMain {
  static function main():Void {
    var seed = Resource.getString('bootstrap_image');
    if (seed == null) throw 'Missing stage-zero image';
    var source = 'nail ' + numeric.LanguageVersion.CURRENT
      + ' ;\n' + File.getContent('stdlib.nail');
    var image = Rebootstrap.verify(seed, source);
    FileSystem.createDirectory('build');
    FileSystem.createDirectory('build/bootstrap');
    File.saveContent('build/bootstrap/self-image.json', image + '\n');
    Sys.println('Reproducible bootstrap: ' + Rebootstrap.fingerprint(image));
  }
}
