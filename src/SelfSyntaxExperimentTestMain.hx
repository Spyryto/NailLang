import haxe.Json;
import haxe.Resource;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.Parser;
import nail.Vm;

/** Isolated first step of self-parser alignment. Named arguments are not
    admitted by this Nail-written parser yet. Compare with the Haxe oracle. */
class SelfSyntaxExperimentTestMain {
  static var passed=0;
  static function ok(condition:Bool,label:String):Void {
    if (!condition) throw 'SELF SYNTAX: '+label;
    passed++;
  }
  static function main():Void {
    var source=Resource.getString('stdlib-experimental');
    if (source==null) throw 'Missing experimental stdlib';
    var library=new Vm(70000000);
    library.runExperimental(source);
    var samples:Array<{code:String,expected:Array<Dynamic>}>=[
      {code:'def add-one x = x + 1 ; 41 >> add-one ;',expected:[42]},
      {code:'def double-it x = x * 2 ; 1 + 2 >> double-it >> double-it ;',expected:[12]},
      {code:'def subtract-from a b = a - b ; 3 >> subtract-from 10 ;',expected:[7]},
      {code:'def keep-1 x = x ; 2 >> ( fun x -> keep-1 ( x + 1 ) ) ;',expected:[3]},
      {code:'def pass-through x = x ; " >> " >> pass-through ;',expected:['>>']},
      {code:'def choose-it x = x ; if true then 2 >> choose-it else 0 ;',expected:[2]}
    ];
    for (sample in samples) {
      var oracle=new Vm(70000000).runPlainExperimental(sample.code);
      ok(Json.stringify(oracle)==Json.stringify(sample.expected),'host expected '+sample.code);
      ok(Json.stringify(library.runPlainWithNail(sample.code))==Json.stringify(oracle),
        'Nail evaluator agrees '+sample.code);
      var host=BytecodeCompiler.compile(new Parser(sample.code,null,true).parse());
      ok(BootstrapImage.encode(host)==BootstrapImage.encode(library.compileWithNail(sample.code)),
        'Nail compiler bytecode agrees '+sample.code);
    }
    for (code in ['def bad--name x = x ;','def bad- x = x ;','def -bad x = x ;',
      '1 >> ;','def pair x y = x ; pair y: 2 x: 1 ;']) {
      var refused=false;
      try library.runPlainWithNail(code) catch (_:Dynamic) refused=true;
      ok(refused,'unsupported or malformed syntax rejected '+code);
    }
    var stable=new Vm(70000000);
    stable.loadStdlib();
    for (code in ['def new-name x = x ;','1 >> ( fun x -> x ) ;']) {
      var refused=false;
      try stable.runPlainWithNail(code) catch (_:Dynamic) refused=true;
      ok(refused,'official self-parser remains unchanged '+code);
    }
    trace('Self syntax experiment: '+passed+' differential checks passed');
  }
}
