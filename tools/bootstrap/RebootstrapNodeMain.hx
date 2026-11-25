import nail.Rebootstrap;

/** Fast Node-driven build of the same modern Nail bootstrap fixed point as
    RebootstrapImageMain -- no Haxe host parser is loaded by this stage.
    The Haxe --interp recipe remains available for Haxe-only builds. */
class RebootstrapNodeMain {
  public static function main():Void {
    #if js
    var fs:Dynamic=js.Syntax.code("require('node:fs')");
    #if nail_syntax_candidate
    var input='build/tests/stdlib-experimental.nail';
    var output='build/bootstrap-candidate';
    #else
    var input='stdlib.nail';
    var output='build/bootstrap';
    #end
    var seed:String=cast fs.readFileSync(
      output+'/stdlib-image.json','utf8');
    var source:String='nail ' + numeric.LanguageVersion.CURRENT + ' ;\n'
      + cast(fs.readFileSync(input,'utf8'),String);
    var image=Rebootstrap.verify(seed,source);
    fs.mkdirSync(output,{recursive:true});
    fs.writeFileSync(output+'/self-image.json',image+'\n','utf8');
    trace('Reproducible modern Node bootstrap: '+Rebootstrap.fingerprint(image));
    #else
    throw 'This bootstrap build entry point requires Node.js';
    #end
  }
}
