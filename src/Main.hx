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

  /** Structured source inspection for tooling; no runtime execution or LSP. */
  public static function analyze(source:String, ?modules:String->Null<String>):nail.SourceAnalysis.AnalysisResult
    return nail.SourceAnalysis.analyze(source, modules);

  /** Isolated syntax experiment: the official API above remains unchanged. */
  public static function analyzeExperimental(source:String):nail.SourceAnalysis.AnalysisResult
    return nail.SourceAnalysis.analyze(source,null,true);

  public static function expandExperimental(source:String):String
    return nail.ExpansionView.render(new nail.Parser(source,null,true).parse());

  /** Execute structured Nail bytecode with the shared primitive runtime. */
  public static function createByteVm(maxSteps:Int = 100000):ByteVm return new ByteVm(maxSteps);

  public static function expand(source:String, ?modules:String->Null<String>):String
    return nail.ExpansionView.render(new nail.Parser(source).parse(modules));

  static function main():Void {
    #if php
    // php build/php/index.php example.nail
    // php build/php/index.php --types example.nail
    var options = nail.CliMacroModules.read(Sys.args());
    var paths = options.paths;
    var modules = options.modules;
    var typeMode = paths.length > 0 && paths[0] == '--types';
    var selfMode = paths.length > 0 && paths[0] == '--selfparse';
    var byteMode = paths.length > 0 && paths[0] == '--bytecode';
    var expandMode = paths.length > 0 && paths[0] == '--expand';
    if (typeMode || selfMode || byteMode || expandMode) paths.shift();
    if (paths.length == 0) return;
    if (expandMode) {
      for (path in paths) Sys.println(expand(sys.io.File.getContent(path), modules));
    } else if (typeMode) {
      var types = createTypeChecker();
      types.check(haxe.Resource.getString('stdlib'));
      for (path in paths) for (type in types.check(sys.io.File.getContent(path), modules)) Sys.println(type);
    } else {
      var vm = selfMode || byteMode ? create(25000000) : create();
      vm.loadStdlib();
      var byteVm = byteMode ? createByteVm() : null;
      if (byteMode) byteVm.run(BytecodeCompiler.compileSource(haxe.Resource.getString('stdlib')));
      for (path in paths) {
        var code = sys.io.File.getContent(path);
        var results = byteMode ? byteVm.runPlain(vm.compileWithNail(code, modules))
          : selfMode ? vm.runPlainWithNail(code, modules) : vm.runPlain(code, modules);
        for (v in results) Sys.println(haxe.Json.stringify(v));
      }
    }
    #end
  }
}

