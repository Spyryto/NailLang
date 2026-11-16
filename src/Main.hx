import nail.Vm;

/** Tiny target adapters; the parser and evaluator have no platform branches. */
@:expose('NailSeed')
class Main {
  /** In JavaScript: var vm = NailSeed.create(); vm.loadStdlib(); vm.runPlain(...); */
  public static function create(maxSteps:Int = 100000):Vm return new Vm(maxSteps);

  static function main():Void {
    #if php
    // Optional CLI: php build/php/index.php example.nail
    var paths = Sys.args();
    if (paths.length == 0) return;
    var vm = create();
    vm.loadStdlib();
    for (path in paths) {
      var results = vm.runPlain(sys.io.File.getContent(path));
      for (v in results) Sys.println(haxe.Json.stringify(v));
    }
    #end
  }
}
