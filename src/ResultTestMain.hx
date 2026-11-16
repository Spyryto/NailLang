import haxe.Json;
import nail.BootstrapImage;
import nail.BootRuntime;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.ModuleLinker;
import nail.ModuleLinker.ModuleCallOutcome;
import nail.NType;
import nail.TypeChecker;
import nail.Value;
import nail.Vm;

/** v0.32: Result is ordinary Nail ADT code, module-lookup failures are
    recoverable host values, and runtime faults never become Result.Err. */
class ResultTestMain {
  static var passed = 0;

  static function check(condition:Bool, label:String):Void {
    if (!condition) throw 'RESULT TEST FAILED: ' + label;
    passed++;
  }

  static function fails(action:Void->Void, needle:String):Void {
    var message = '';
    try action() catch (e:Dynamic) message = Std.string(e);
    check(message.indexOf(needle) >= 0,
      'expected "' + needle + '", got "' + message + '"');
  }

  public static function main():Void {
    var library = haxe.Resource.getString('result_source');
    check(library != null && library.indexOf('type Result a e') >= 0,
      'result example is a real Nail source file');
    var expressions = [
      'unwrapOr ( resultMap ( fun x -> x * 2 ) ( safeDivide 20 4 ) ) 0 ;',
      'unwrapOr ( safeDivide 5 0 ) -1 ;',
      'unwrapOr ( safeRatio 18 3 ) -1 ;',
      'unwrapOr ( safeRatio -18 3 ) -1 ;',
      'explain ( safeDivide 5 0 ) ;',
      'explain ( safeRatio -18 3 ) ;',
      'explain ( resultMapError ( fun err -> NegativeInput ) ( safeDivide 5 0 ) ) ;'
    ];
    var expected:Array<Dynamic> = [10, -1, 6, -1, 'zero', 'negative', 'negative'];
    var program = library + '\n' + expressions.join('\n');
    var types = new TypeChecker();
    var inferred = types.check(program);
    check(inferred.length == expressions.length,
      'type checker accepts all recoverable result expressions');
    check(types.signature('safeDivide').indexOf('Result[') >= 0,
      'Result remains statically typed and inferred');
    check(types.signature('resultBind').indexOf('Result[') >= 0,
      'bind is checked as a regular polymorphic Nail function');
    var plain = Json.stringify(expected);
    check(Json.stringify(new Vm(25000000).runPlain(program)) == plain,
      'AST VM composes Ok and Err without raising exceptions');

    var reference = BytecodeCompiler.compileSource(program);
    var selfHosted = new BootRuntime(25000000);
    var fromNail = selfHosted.compile(program);
    check(BootstrapImage.encode(reference) == BootstrapImage.encode(fromNail),
      'Nail-written compiler emits the same Result bytecode');
    check(Json.stringify(new ByteVm(25000000).runPlain(fromNail)) == plain,
      'bytecode VM executes typed Result branches');
    check(Json.stringify(selfHosted.runPlain(program)) == plain,
      'source-free bootstrap executes typed Result branches');

    fails(() -> new TypeChecker().check(
      'type Result a e = Ok a | Err e ; def bad x = if true then Ok x else x ;'),
      'Type error:');
    fails(() -> new Vm().runPlain('1 / 0 ;'), 'Division by zero');

    // Module lookup errors are explicit, typed Haxe outcomes.
    var spec:nail.ModuleLinker.SourceModuleSpec = {
      name:'Simple',
      source:'def double n = n * 2 ; def explode n = n / 0 ;',
      imports:[],
      exports:[
        {name:'double',type:TFunction(TNumber,TNumber)},
        {name:'explode',type:TFunction(TNumber,TNumber)}
      ]
    };
    var compiled = ModuleLinker.compile(spec);
    var linked = ModuleLinker.linkImages([nail.ModuleImage.encode(compiled)]);
    switch (linked.tryInvoke('Simple', 'double', Number(5))) {
      case CallSuccess(Number(n)): check(n == 10, 'successful typed module invocation');
      case _: check(false, 'expected successful module invocation');
    }
    switch (linked.tryInvoke('Unknown', 'double', Number(5))) {
      case MissingModule(name): check(name == 'Unknown', 'missing module is recoverable');
      case _: check(false, 'expected missing module');
    }
    switch (linked.tryInvoke('Simple', 'privateFn', Number(5))) {
      case MissingExport(name, symbol):
        check(name == 'Simple' && symbol == 'privateFn',
          'private/missing exports are recoverable');
      case _: check(false, 'expected missing export');
    }
    // The boundary MUST NOT catch computation errors. No fake Err is returned.
    fails(() -> { linked.tryInvoke('Simple', 'explode', Number(3)); },
      'Division by zero');
    fails(() -> { linked.invoke('Unknown', 'double', Number(5)); },
      'unknown module Unknown');

    trace('NailSeed v0.32 recoverable Result slice: ' + passed + ' checks passed');
  }
}
