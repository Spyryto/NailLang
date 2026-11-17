import nail.Rebootstrap;

/** Fast Node-driven build of the same modern Nail bootstrap fixed point as
    RebootstrapImageMain -- no Haxe host parser is loaded by this stage.
    The Haxe --interp recipe remains available for Haxe-only builds. */
class RebootstrapNodeMain {
  public static function main():Void {
    #if js
    var fs:Dynamic=js.Syntax.code("require('node:fs')");
    var seed:String=cast fs.readFileSync(
      'build/bootstrap/stdlib-image.json','utf8');
    var source:String='nail ' + numeric.LanguageVersion.CURRENT + ' ;\n'
      + cast(fs.readFileSync('stdlib.nail','utf8'),String);
    var image=Rebootstrap.verify(seed,source);
    fs.mkdirSync('build/bootstrap',{recursive:true});
    fs.writeFileSync('build/bootstrap/self-image.json',image+'\n','utf8');
    trace('Reproducible modern Node bootstrap: '+Rebootstrap.fingerprint(image));
    #else
    throw 'This bootstrap build entry point requires Node.js';
    #end
  }
}
