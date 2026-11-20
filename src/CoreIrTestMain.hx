import haxe.Json;
import nail.Parser;
import nail.Value;
import nail.CoreIR;
import nail.CoreIR.CoreExpr;
import nail.CoreIR.CoreForm;
import nail.BytecodeCompiler;
import nail.BootstrapImage;
import nail.ByteVm;
import nail.RuntimeValues;

/** Differential semantic gate for the first independent CoreIR boundary. */
class CoreIrTestMain {
  static var checks=0;
  static function ok(condition:Bool,label:String):Void {
    if(!condition) throw "CORE IR: "+label;
    checks++;
  }
  static function rejects(f:Void->Void,needle:String):Void {
    var message="";
    try f() catch(e:Dynamic) message=Std.string(e);
    ok(message.indexOf(needle)>=0,
      "expected "+needle+" in "+message);
  }
  public static function main():Void {
    for(source in [
      'nail 0.60 ; def id x = x ; id 42 ;',
      'nail 0.55 ; def choose flag = if flag then 7 else 9 ; choose true ;',
      'nail 0.55 ; def apply f x = f x ; def id x = x ; apply id 42 ;',
      'nail 0.55 ; def choose flag = if flag then 7 else 9 ; choose false ;',
      'nail 0.55 ; type Box { value Int } ; type Choice = No | Yes Int ; match Yes ( ( Box 42 ) . value ) with | No -> 0 | Yes n -> n ;'
    ]) {
      var original=new Parser(source).parse();
      var reference=BytecodeCompiler.compile(original);
      var ir=CoreIR.lower(original);
      var restored=CoreIR.raise(ir);
      var translated=BytecodeCompiler.compile(restored);
      var direct=CoreIR.compile(original);
      ok(BootstrapImage.encode(reference)==BootstrapImage.encode(translated),
        'CoreIR lowering/raising preserves exact reference bytecode: '+source);
      ok(BootstrapImage.encode(reference)==BootstrapImage.encode(direct),
        'CoreIR codegen bridge preserves reference bytecode: '+source);
      var expected=RuntimeValues.plainResults(new ByteVm().run(reference));
      var actual=RuntimeValues.plainResults(new ByteVm().run(direct));
      ok(Json.stringify(expected)==Json.stringify(actual),
        'CoreIR preserves evaluated values and order: '+source);
    }

    // A crafted IR cannot claim a non-tail call is a terminal operation, or
    // permit a tail call in the condition of an if expression.
    rejects(() -> CoreIR.raise([CExecute(
      CInvoke(CRead('id'),CValue(Boolean(true)),false))]),
      'tail call marker does not match');
    rejects(() -> CoreIR.raise([CExecute(
      CChoose(CRead('flag'),CValue(Boolean(true)),
        CValue(Boolean(false)),false))]),
      'tail branch marker does not match');
    rejects(() -> CoreIR.raise([CExecute(
      CChoose(CInvoke(CRead('id'),CValue(Boolean(true)),true),
        CValue(Boolean(true)),CValue(Boolean(false)),true))]),
      'tail call marker does not match');
    rejects(() -> CoreIR.raise([CExecute(CRead(''))]),
      'invalid read name');

    var deliberate=CoreIR.raise([
      CDefine('id',CFunction('x',CRead('x'))),
      CExecute(CInvoke(CRead('id'),CValue(Boolean(true)),true))
    ]);
    ok(Json.stringify(RuntimeValues.plainResults(
      new ByteVm().run(BytecodeCompiler.compile(deliberate))))
        ==Json.stringify([true]),
      'direct CoreIR construction can execute after tail validation');
    trace('CoreIR: '+checks+' cross-target differential checks passed');
  }
}
