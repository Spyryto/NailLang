import haxe.Json;
import sys.FileSystem;
import sys.io.File;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.Vm;

/** Build-time image generator. THIS is the stage that uses the Haxe parser.
    Its output is data embedded into the separately compiled boot runtime. */
class BootstrapImageMain {
  static function main():Void {
    var source = 'nail ' + numeric.LanguageVersion.CURRENT
      + ' ;\n' + File.getContent('stdlib.nail');
    var bytecode = BytecodeCompiler.compileSource(source);
    var encoded = BootstrapImage.encodeModern(bytecode);
    var roundTrip = BootstrapImage.decode(encoded);
    if (Json.stringify(Vm.toPlain(bytecode)) != Json.stringify(Vm.toPlain(roundTrip)))
      throw 'Bootstrap image failed round-trip validation';
    FileSystem.createDirectory('build');
    FileSystem.createDirectory('build/bootstrap');
    File.saveContent('build/bootstrap/stdlib-image.json', encoded + '\n');
    Sys.println('Modern bootstrap image for Nail '
      + numeric.LanguageVersion.CURRENT + ' generated ('
      + encoded.length + ' characters)');
  }
}
