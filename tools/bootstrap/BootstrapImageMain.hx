import sys.FileSystem;
import sys.io.File;
import nail.BootstrapImage;
import nail.BytecodeCompiler;

/** Build-time image generator. THIS is the stage that uses the Haxe parser.
    Its output is data embedded into the separately compiled boot runtime. */
class BootstrapImageMain {
  static function main():Void {
    #if nail_syntax_candidate
    var input = 'build/tests/stdlib-experimental.nail';
    var output = 'build/bootstrap-candidate';
    #else
    var input = 'stdlib.nail';
    var output = 'build/bootstrap';
    #end
    var source = 'nail ' + numeric.LanguageVersion.CURRENT
      + ' ;\n' + File.getContent(input);
    #if nail_syntax_candidate
    var bytecode = BytecodeCompiler.compile(new nail.Parser(source,null,true).parse());
    #else
    var bytecode = BytecodeCompiler.compileSource(source);
    #end
    var encoded = BootstrapImage.encodeModern(bytecode);
    // Stage zero must not depend on the AST execution VM: verify the entire
    // portable bytecode image at the serialization boundary instead.
    var roundTrip = BootstrapImage.decode(encoded);
    if (BootstrapImage.encodeModern(roundTrip) != encoded)
      throw 'Stage-zero image failed deterministic round-trip validation';
    FileSystem.createDirectory('build');
    FileSystem.createDirectory(output);
    File.saveContent(output + '/stdlib-image.json', encoded + '\n');
    Sys.println('Modern bootstrap image for Nail '
      + numeric.LanguageVersion.CURRENT + ' generated ('
      + encoded.length + ' characters)');
  }
}
