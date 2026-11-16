package nail;

#if sys
class CliMacroModules {
  public static function read(args:Array<String>):{paths:Array<String>, modules:Null<String->Null<String>>} {
    if (args[0] != '--macro-dir') return {paths:args, modules:null};
    if (args.length < 3) throw 'Usage: --macro-dir DIR [mode] FILE ...';
    var directory = args[1];
    if (!sys.FileSystem.exists(directory) || !sys.FileSystem.isDirectory(directory))
      throw 'Macro directory does not exist: ' + directory;
    return {
      paths:args.slice(2),
      modules:name -> {
        var file = haxe.io.Path.join([directory, name + '.nail']);
        if (!sys.FileSystem.exists(file) || sys.FileSystem.isDirectory(file)) return null;
        return sys.io.File.getContent(file);
      }
    };
  }
}
#end
