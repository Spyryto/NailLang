import nail.Vm;
import nail.TypeChecker;
import nail.ByteVm;
import nail.BytecodeCompiler;

/** Thin target adapters. Type inference never changes the five-node VM core. */
@:expose('NailSeed')
class Main {
  public static function create(maxSteps:Int = 100000):Vm return new Vm(maxSteps);

  /** Optional static checker; calls to .check(source) persist top-level signatures. */
  public static function createTypeChecker():TypeChecker return new TypeChecker();

  /** Execute structured Nail bytecode with the shared primitive runtime. */
  public static function createByteVm(maxSteps:Int = 100000):ByteVm return new ByteVm(maxSteps);

  public static function expand(source:String):String
    return nail.ExpansionView.render(new nail.Parser(source).parse());

  static function main():Void {
    #if php
    // php build/php/index.php example.nail
    // php build/php/index.php --types example.nail
    var paths = Sys.args();
    var typeMode = paths.length > 0 && paths[0] == '--types';
    var selfMode = paths.length > 0 && paths[0] == '--selfparse';
    var byteMode = paths.length > 0 && paths[0] == '--bytecode';
    var expandMode = paths.length > 0 && paths[0] == '--expand';
    if (typeMode || selfMode || byteMode || expandMode) paths.shift();
    if (paths.length == 0) return;
    if (expandMode) {
      for (path in paths) Sys.println(expand(sys.io.File.getContent(path)));
    } else if (typeMode) {
      var types = createTypeChecker();
      types.check(haxe.Resource.getString('stdlib'));
      for (path in paths) for (type in types.check(sys.io.File.getContent(path))) Sys.println(type);
    } else {
      var vm = create();
      vm.loadStdlib();
      var byteVm = byteMode ? createByteVm() : null;
      if (byteMode) byteVm.run(BytecodeCompiler.compileSource(haxe.Resource.getString('stdlib')));
      for (path in paths) {
        var code = sys.io.File.getContent(path);
        var results = byteMode ? byteVm.runPlain(vm.compileWithNail(code))
          : selfMode ? vm.runPlainWithNail(code) : vm.runPlain(code);
        for (v in results) Sys.println(haxe.Json.stringify(v));
      }
    }
    #end
  }
}

