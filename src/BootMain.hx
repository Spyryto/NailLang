import haxe.Json;
import nail.BootRuntime;

/** Standalone JS/PHP distribution with bytecode-only boot. */
@:expose('NailSeedBoot')
class BootMain {
  public static function create(maxSteps:Int = 25000000):BootRuntime return new BootRuntime(maxSteps);

  static function main():Void {
    #if php
    // php build/boot/php/index.php program.nail [another.nail ...]
    for (path in Sys.args()) {
      var vm = create();
      for (result in vm.runPlain(sys.io.File.getContent(path)))
        Sys.println(Json.stringify(result));
    }
    #end
  }
}
