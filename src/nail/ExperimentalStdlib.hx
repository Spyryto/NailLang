package nail;

import haxe.Resource;

/** Dogfooding adapter. The patched bootstrap library deliberately keeps
    its original numeric dialect. Only the independently checked list and
    collection section is exposed to static analysis of user programs. */
class ExperimentalStdlib {
  static var checkedPrelude:Null<TypeChecker>;

  static function source():String {
    var value=Resource.getString('stdlib');
    if (value==null) throw 'Missing canonical stdlib';
    return value;
  }

  static function requireLegacy(code:String):Void {
    if (numeric.LanguageVersion.isModern(code) || numeric.NumericDialect.isExact(code))
      throw 'Experimental stdlib uses legacy Number semantics; remove the nail version header or select the 0.62 syntax mode';
  }

  static function environment():TypeChecker {
    if (checkedPrelude==null) {
      var text=source();
      var marker='# v0.37 collections END';
      var stop=text.indexOf(marker);
      if (stop<0) throw 'Missing experimental collections section';
      var checker=new TypeChecker();
      checker.checkExperimental(text.substr(0,stop+marker.length));
      checkedPrelude=checker;
    }
    return checkedPrelude;
  }

  public static function analyze(code:String):SourceAnalysis.AnalysisResult {
    try requireLegacy(code) catch (error:Dynamic)
      return {ok:false,version:null,diagnostics:[{phase:'type',message:Std.string(error),span:null}],
        symbols:[],references:[],evaluations:[]};
    return SourceAnalysis.analyze(code,null,true,environment());
  }

  public static function expand(code:String):String {
    requireLegacy(code);
    return ExpansionView.render(environment().experimentalParser(code).parse());
  }

  public static function run(code:String,maxSteps:Int):Array<Dynamic> {
    requireLegacy(code);
    var report=analyze(code);
    if (!report.ok) throw report.diagnostics[0].message;
    var vm=new Vm(maxSteps);
    vm.runExperimental(source());
    return vm.runPlainExperimental(code);
  }
}
