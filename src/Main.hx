import nail.Vm;
import nail.TypeChecker;

/** Thin target adapters. Type inference never changes the five-node VM core. */
@:expose('NailSeed')
class Main {
  public static function create(maxSteps:Int = 100000):Vm return new Vm(maxSteps);

  /** Optional static checker; calls to .check(source) persist top-level signatures. */
  public static function createTypeChecker():TypeChecker return new TypeChecker();

  static function main():Void {
    #if php
    // php build/php/index.php example.nail
    // php build/php/index.php --types example.nail
    var paths = Sys.args();
    var typeMode = paths.length > 0 && paths[0] == '--types';
    var selfMode = paths.length > 0 && paths[0] == '--selfparse';
    if (typeMode || selfMode) paths.shift();
    if (paths.length == 0) return;
    if (typeMode) {
      var types = createTypeChecker();
      types.check(haxe.Resource.getString('stdlib'));
      for (path in paths) for (type in types.check(sys.io.File.getContent(path))) Sys.println(type);
    } else {
      var vm = create();
      vm.loadStdlib();
      for (path in paths) {
        var results = selfMode ? vm.runPlainWithNail(sys.io.File.getContent(path)) : vm.runPlain(sys.io.File.getContent(path));
        for (v in results) Sys.println(haxe.Json.stringify(v));
      }
    }
    #end
  }
}
