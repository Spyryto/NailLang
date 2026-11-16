import haxe.Json;
import nail.BootRuntime;

/** Standalone JS/PHP distribution with bytecode-only boot. */
@:expose('NailSeedBoot')
class BootMain {
  public static function create(maxSteps:Int = 25000000):BootRuntime return new BootRuntime(maxSteps);

  static function main():Void {
    #if php
    // php build/boot/php/index.php program.nail [another.nail ...]
    var options = nail.CliMacroModules.read(Sys.args());
    for (path in options.paths) {
      var vm = create();
      for (result in vm.runPlain(sys.io.File.getContent(path), options.modules))
        Sys.println(Json.stringify(result));
    }
    #end
  }
}

