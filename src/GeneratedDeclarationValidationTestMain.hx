import haxe.Json;
import nail.Ast.Expr;
import nail.Ast.Form;
import nail.BootstrapImage;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.SourcePositions;
import nail.GeneratedDeclarationValidator;
import nail.SyntaxBridge;
import nail.SyntaxEncoder;
import nail.TypeChecker;
import nail.NType;
import nail.Parser;
import nail.Value;
import nail.Vm;

/** Contract check, intentionally independent of the Nail transformer source. */
class GeneratedDeclarationValidationTestMain {
  static var checks = 0;
  static function ok(cond:Bool, message:String):Void {
    if (!cond) throw 'GENERATED CONTRACT: ' + message;
    checks++;
  }

  static function fails(action:Void->Void, needle:String):Void {
    var message = '';
    try action() catch (e:Dynamic) message = Std.string(e);
    ok(message.indexOf(needle) >= 0, 'expected "' + needle + '", got ' + message);
  }

  static function list(values:Array<Value>):Value {
    var result:Value = Nil;
    var n = values.length;
    while (n > 0) result = Cons(values[--n], result);
    return result;
  }

  static function plan(source:Value, runtime:Value):Value
    return SyntaxNode('RecordExpansion', list([source, runtime]));

  static function parts(p:Value):Array<Value> return switch (p) {
    case SyntaxNode('RecordExpansion', Cons(source, Cons(runtime, Nil))): [source,runtime];
    case _: throw 'expected plan';
  };

  public static function main():Void {
    var vm = new Vm(50000000);
    vm.loadStdlib();

    var wide = 'type Wide { ';
    for (i in 0...128) wide += 'f' + i + ' Number ';
    wide += '} ;';

    var examples = [
      '',
      'def id x = x ; id 7 ;',
      'type Person { name Text age Number } ; def p = Person " Ada " 32 ; p . age ;',
      'type Person { name Text } ; type Badge { owner Person valid Bool } ; '
        + '( Badge ( Person " Ada " ) true ) . owner . name ;',
      'type A { value Number } ; type B { value Text } ; ( B " yes " ) . value ;',
      'type Option a = None | Some a ; type Box { value Number } ; '
        + 'match Some ( Box 42 ) with | None -> 0 | Some x -> x . value ;',
      wide
    ];
    for (source in examples) {
      var expansion = vm.expandRecordsWithNail(source);
      var p = parts(expansion);
      var before = BootstrapImage.encode(p[1]);
      var accepted = GeneratedDeclarationValidator.validate(expansion);
      ok(BootstrapImage.encode(accepted) == before, 'valid expansion accepted unchanged');
      ok(BootstrapImage.encode(vm.validatedRecordsWithNail(source)) == before,
        'VM validation API uses contract');
    }

    var sample = 'type Person { name Text age Number } ; '
      + '( Person " Ada " 32 ) . age ;';
    var valid = vm.expandRecordsWithNail(sample);
    var p = parts(valid);
    var output = SyntaxBridge.forms(p[1]);
    ok(output.length == 4, 'constructor, two getters and expression emitted');

    var dropGetter = output.copy();
    dropGetter.splice(2, 1);
    fails(() -> GeneratedDeclarationValidator.validate(plan(p[0], SyntaxEncoder.program(dropGetter))),
      'form count');

    var extra = output.copy();
    extra.push(Evaluate(Literal(Number(100))));
    fails(() -> GeneratedDeclarationValidator.validate(plan(p[0], SyntaxEncoder.program(extra))),
      'form count');

    var wrongGetter = output.copy();
    wrongGetter[1] = Define('Person.name', Lambda('#rec', Literal(Number(44))));
    fails(() -> GeneratedDeclarationValidator.validate(plan(p[0], SyntaxEncoder.program(wrongGetter))),
      'mismatch at form 1 (Person)');

    var renamed = output.copy();
    renamed[0] = Define('PersonBad', switch (output[0]) {
      case Define(_, body): body;
      case _: throw 'expected constructor';
    });
    fails(() -> GeneratedDeclarationValidator.validate(plan(p[0], SyntaxEncoder.program(renamed))),
      'mismatch at form 0 (Person)');

    fails(() -> GeneratedDeclarationValidator.validate(SyntaxNode('RecordExpansion', Nil)),
      'expected RecordExpansion');
    fails(() -> GeneratedDeclarationValidator.validate(vm.expandRecordsWithNail(
      'type Invalid { field Missing } ;')), 'unknown record field type');
    fails(() -> GeneratedDeclarationValidator.validate(vm.expandRecordsWithNail(
      'type Person { age Number } ; Person true ;')), 'cannot unify');

    var modules = (name:String) -> name == 'records'
      ? 'macro make x = quote ( T ( unquote x ) ) ; export make ;'
      : null;
    var imported = 'import make from records ; type T { x Number } ; '
      + '( expand make 12 ) . x ;';
    ok(BootstrapImage.encode(vm.validatedRecordsWithNail(imported, modules))
      == BootstrapImage.encode(parts(vm.expandRecordsWithNail(imported, modules))[1]),
      'imported expression macros and generated declarations compose');

    var validated = vm.compileValidatedWithNail(sample);
    ok(BootstrapImage.encode(validated) == BootstrapImage.encode(vm.compileWithNail(sample)),
      'validation leaves canonical emitted bytecode untouched');
    ok(Json.stringify(new ByteVm(50000000).runPlain(validated)) == '[32]',
      'validated compilation executes identically');

    // General host-side signature contracts: this code need not come from the
    // trusted record transformer. It can be arbitrary generated Syntax, but
    // each exported declaration must meet a closed, explicit type signature.
    var baseline = SyntaxEncoder.program(new Parser('type Person { age Number } ;').parseRaw());
    var fragment = SyntaxEncoder.program(new Parser(
      'def age person = person . age ; '
      + 'def inc n = n + 1 ; '
      + 'def twice n = inc ( inc n ) ;').parseRaw());
    var numeric:NType = TFunction(TNumber, TNumber);
    var general = [
      {name:'age', type:TFunction(TRecord('Person'), TNumber)},
      {name:'inc', type:numeric},
      {name:'twice', type:numeric}
    ];
    var isolated = new TypeChecker();
    var initialNames = isolated.names().length;
    var signatures = isolated.checkGenerated(baseline, fragment, general);
    ok(signatures.length == 3 && signatures[0] == 'Person -> Number'
      && signatures[1] == 'Number -> Number'
      && signatures[2] == 'Number -> Number', 'generic generated contracts typed');
    ok(isolated.names().length == initialNames,
      'generated checking does not mutate caller checker');

    var numberSource = SyntaxEncoder.program([]);
    function generated(text:String):Value
      return SyntaxEncoder.program(new Parser(text).parseRaw());

    ok(new TypeChecker().checkGenerated(numberSource,
      generated('def countdown n = if n == 0 then 0 else countdown ( n - 1 ) ;'),
      [{name:'countdown', type:numeric}]).length == 1,
      'monomorphic recursive generated definition');
    ok(new TypeChecker().checkGenerated(
      generated('def base = 4 ;'), generated('def addBase n = n + base ;'),
      [{name:'addBase', type:numeric}]).length == 1,
      'generated definition references checked source binding');

    fails(() -> new TypeChecker().checkGenerated(numberSource,
      generated('def bad n = true ;'), [{name:'bad', type:numeric}]),
      'cannot unify');
    fails(() -> new TypeChecker().checkGenerated(numberSource,
      generated('def bad n = missing n ;'), [{name:'bad', type:numeric}]),
      'unknown name missing');
    fails(() -> new TypeChecker().checkGenerated(numberSource,
      generated('def x = 1 ; def y = 2 ;'), [{name:'x', type:TNumber}]),
      'definition count');
    fails(() -> new TypeChecker().checkGenerated(numberSource,
      generated('def x = 1 ;'), [{name:'y', type:TNumber}]),
      'expected y');
    fails(() -> new TypeChecker().checkGenerated(numberSource,
      generated('def x = 1 ; def x = 2 ;'),
      [{name:'x', type:TNumber}, {name:'x', type:TNumber}]),
      'duplicate or existing definition x');
    fails(() -> new TypeChecker().checkGenerated(numberSource,
      generated('def base = 5 ;'), [{name:'base', type:TRecord('Ghost')}]),
      'unknown record type Ghost');
    fails(() -> new TypeChecker().checkGenerated(numberSource,
      generated('def x = 5 ;'), [{name:'x', type:TVariable(17)}]),
      'polymorphic signatures');
    fails(() -> new TypeChecker().checkGenerated(numberSource,
      SyntaxEncoder.program([Define('#recordMake', Literal(Number(1)))]),
      [{name:'#recordMake', type:TNumber}]), 'invalid definition name');
    fails(() -> new TypeChecker().checkGenerated(numberSource,
      generated('2 ;'), [{name:'x', type:TNumber}]),
      'expected definition x');
    fails(() -> new TypeChecker().checkGenerated(
      generated('type Bad { age Missing } ;'),
      generated('def x = 1 ;'), [{name:'x', type:TNumber}]),
      'unknown record field type');

    var checked = GeneratedDeclarationValidator.validateTyped(baseline, fragment, general);
    ok(BootstrapImage.encode(checked) == BootstrapImage.encode(fragment),
      'general validation leaves accepted generated syntax unchanged');
    var invocation = SourcePositions.span(
      SourcePositions.scan('\\n  def marker = 3 ;'.split('\\n').join('\n')), 0, 1);
    fails(() -> GeneratedDeclarationValidator.validateTyped(numberSource,
      generated('def bad n = true ;'), [{name:'bad', type:numeric}], invocation),
      'Generated declaration at 2:3:');

    var incProgram = generated('def inc n = n + 1 ;');
    var verifiedBytecode = vm.compileCheckedGenerated(numberSource, incProgram,
      [{name:'inc', type:numeric}]);
    var independentBytecode = BytecodeCompiler.compileSyntax(incProgram);
    ok(BootstrapImage.encode(verifiedBytecode)
      == BootstrapImage.encode(independentBytecode),
      'general validation preserves deterministic compiler output');
    var machine = new ByteVm(1000000);
    machine.run(verifiedBytecode);
    ok(Json.stringify(machine.runPlain(BytecodeCompiler.compileSource('inc 2 ;')))
      == '[3]', 'general generated program executes after signature validation');

    trace('NailSeed v0.27 generated declaration contract: ' + checks + ' passed');
  }
}
