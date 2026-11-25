import haxe.Json;
import haxe.Resource;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.ByteVm;
import nail.Parser;
import nail.TypeChecker;
import nail.Value;
import nail.Vm;

/** Compare the actual whole standard library with its patched counterpart.
    Both are unversioned bootstrap sources; only the surface parser differs. */
class StdlibSyntaxExperimentTestMain {
  static var passed=0;
  static inline var budget=70000000;
  static function ok(condition:Bool,label:String):Void {
    if (!condition) throw 'STDLIB SYNTAX EXPERIMENT: '+label;
    passed++;
  }
  static function same(actual:Dynamic,expected:Dynamic,label:String):Void
    ok(Json.stringify(actual)==Json.stringify(expected),label);
  static function prefix(source:String):String {
    var end='# v0.37 collections END';
    var at=source.indexOf(end);
    if (at<0) throw 'Missing collections section';
    return source.substr(0,at+end.length)+'\n';
  }
  static function main():Void {
    var original=Resource.getString('stdlib');
    var revised=Resource.getString('stdlib-experimental');
    ok(original!=null && revised!=null && original!=revised,'real patched resource');
    var stable=new Vm(budget);
    stable.loadStdlib();
    var experimental=new Vm(budget);
    experimental.runExperimental(revised);
    var before=stable.names();
    var after=experimental.names();
    ok(after.indexOf('tokenize-at')>=0,'hyphenated implementation');
    after.remove('tokenize-at');
    same(after,before,'all existing exported runtime names retained');

    // Compare values from the complete libraries, not just test fixtures.
    var samples=[
      'compose ( fun x -> x + 1 ) ( fun x -> x * 2 ) 20 ;',
      'map ( fun x -> x + 1 ) [ 1 , 2 , 3 ] ; filter ( fun x -> x > 1 ) [ 1 , 2 , 3 ] ; fold ( fun a x -> a + x ) 0 [ 1 , 2 , 3 ] ; reverse [ 1 , 2 , 3 ] ; length [ 1 , 2 , 3 ] ;',
      'def m = mapPut ( mapPut mapEmpty " a " 1 ) " a " 2 ; mapContains m " a " ; mapContains ( mapDelete m " a " ) " a " ; match mapFind m " a " with | MapMissing -> 0 | MapFound n -> n ;',
      'def s = setAdd ( setAdd setEmpty " a " ) " a " ; setContains s " a " ; setContains ( setDelete s " a " ) " a " ; length s ;',
      'tokenize " def square x = x * 2 ; " ; tokenizeAt " a b " 0 3 " " [] ; parseTinyDef " def square x = x * 2 ; " ;',
      'parseTinyDef " invalid " ; tokenize " " ;',
      'parseSource " def x = 42 ; x ; " ;',
      'parseSource " def broken = ; " ;',
      'tcCheckSource " nail 0.61 ; def identity x = x ; identity true ; " ;',
      'tcCheckSourceTraced " nail 0.61 ; true true ; " ;',
      'tcCheckSourceSchemes " nail 0.61 ; def identity x = x ; identity true ; " ;'
    ];
    var referenceResults:Array<Array<Dynamic>>=[];
    for (i in 0...samples.length) {
      var expected=stable.runPlain(samples[i]);
      referenceResults.push(expected);
      same(experimental.runPlain(samples[i]),expected,'whole stdlib AST sample '+i);
    }

    // User programs still use the established grammar when calling the
    // self-hosted parser; that parser has NOT learned the new surface syntax.
    for (program in [
      'def double x = x + x ; double 21 ;',
      'nail 0.61 ; 3 / 2 ;',
      'nail 0.61 ; type Person { name Text } ; def name data = data . name ; name ( Person " Ada " ) ;',
      'nail 0.61 ; macro identity x = x ; identity 42 ;'
    ]) {
      same(experimental.runPlainWithNail(program),stable.runPlainWithNail(program),'self-parser execution: '+program);
      ok(BootstrapImage.encode(experimental.compileWithNail(program))==
        BootstrapImage.encode(stable.compileWithNail(program)),'identical emitted bytecode: '+program);
    }

    // Compile the full patched library through the host parser and execute it
    // on the bytecode VM too; the bootstrap-only image remains unchanged.
    var byteVm=new ByteVm(budget);
    byteVm.run(BytecodeCompiler.compile(new Parser(revised,null,true).parse()));
    for (i in 0...samples.length)
      same(byteVm.runPlain(BytecodeCompiler.compileSource(samples[i])),referenceResults[i],'whole stdlib bytecode sample '+i);

    // Independently check the list/collection slice, including actual
    // renamed labels, currying and generic Eq constraints.
    var oldPrefix=prefix(original), newPrefix=prefix(revised);
    var oldCheck=new TypeChecker(), newCheck=new TypeChecker();
    oldCheck.check(oldPrefix);
    newCheck.checkExperimental(newPrefix);
    for (name in ['compose','map','filter','fold','reverse','length','mapFind','mapContains',
      'mapDelete','mapPut','setContains','setDelete','setAdd'])
      ok(oldCheck.signature(name)==newCheck.signature(name),'same inferred signature: '+name);

    var named='def inc-all = map using: ( fun n -> n + 1 ) ; '
      +'inc-all [ 1 , 2 ] ; '
      +'filter predicate: ( fun n -> n > 1 ) items: [ 1 , 2 , 3 ] ; '
      +'fold initial: 0 using: ( fun acc n -> acc + n ) items: [ 1 , 2 , 3 ] ; '
      +'def table = mapPut mapEmpty value: 2 key: " a " ; '
      +'mapContains table key: " a " ;';
    new TypeChecker().checkExperimental(newPrefix+named);
    same(new Vm(budget).runPlainExperimental(newPrefix+named),[[2,3],[2,3],6,true],
      'real stdlib named calls and partial application in the same source');
    var invalid=false;
    try new TypeChecker().checkExperimental(newPrefix+'setContains entries: [ fun x -> x ] item: ( fun y -> y ) ;')
    catch (e:Dynamic) invalid=Std.string(e).indexOf('functions cannot be compared')>=0;
    ok(invalid,'Eq requirement survives named call');
    trace('Stdlib syntax experiment: '+passed+' differential checks passed');
  }
}
