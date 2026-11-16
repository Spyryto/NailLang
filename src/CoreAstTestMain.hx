import haxe.Json;
import haxe.Resource;
import nail.Value;
import nail.Vm;
import nail.ByteVm;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.TypeChecker;

/** Contract for the ordinary Nail ADT expression IR and compiler boundary. */
class CoreAstTestMain {
  static var passed = 0;
  static function check(ok:Bool, message:String):Void {
    if (!ok) throw 'CORE AST: ' + message;
    passed++;
  }
  static function rejects(action:Void->Void, phrase:String):Void {
    var message = '';
    try action() catch (e:Dynamic) message = Std.string(e);
    check(message.toLowerCase().indexOf(phrase.toLowerCase()) >= 0, 'expected ' + phrase + ', got ' + message);
  }
  static function same(a:Value, b:Value):Bool return BootstrapImage.encode(a) == BootstrapImage.encode(b);

  static function main():Void {
    var vm = new Vm(100000000);
    vm.loadStdlib();
    var checker = new TypeChecker();
    checker.check(Resource.getString('stdlib'));
    check(checker.signature('CoreLambda') == 'Text -> CoreExpr -> CoreExpr', 'recursive constructor type');
    check(checker.signature('coreRead') == 'Syntax -> CoreRead', 'adapter type');
    check(checker.signature('coreCompileGo') == 'CoreExpr -> Bool -> [Syntax]', 'compiler type');
    check(checker.signature('coreToSyntax') == 'CoreExpr -> Syntax', 'reverse adapter type');
    rejects(() -> checker.check('CoreApply ( CoreVar " f " ) 1 ;'), 'type');
    rejects(() -> checker.check('match ( CoreVar " x " ) with | CoreVar x -> x ;'), 'non-exhaustive');
    rejects(() -> checker.check('CoreLit ( CoreNumber 12 ) ;'), 'type');

    // Construct and compile an ordinary ADT without parsing an expression.
    var expression = 'CoreApply ( CoreLambda " x " ( CoreVar " x " ) ) ( CoreLit ( CoreNumber " 42 " ) )';
    var core = vm.run(expression + ' ;')[0];
    var pending = [core];
    var records = 0;
    while (pending.length > 0) switch (pending.pop()) {
      case Record(_, fields): records++; for (value in fields) pending.push(value);
      case Text(_):
      case _: throw 'Core IR contains a special Syntax/other host value';
    }
    check(records == 5, 'IR is recursively ordinary nominal data');
    var codeSource = 'syntaxNode " Bytecode " [ bcInstruction1 " EVAL " ( bcCode ( coreCompileTail ( ' + expression + ' ) ) ) ] ;';
    var direct = vm.run(codeSource)[0];
    check(Json.stringify(new ByteVm().runPlain(direct)) == '[42]', 'direct ADT compilation executes');
    var boot = new BootRuntime(100000000);
    var bootDirect = boot.run(codeSource)[0];
    check(same(direct, bootDirect), 'source-free compiler accepts ADT values');

    var expressions = [
      '42', '-1.25', 'true', 'false', '" hello world "', '[]', 'fun x -> x',
      '( fun x -> x ) 3', 'if true then 1 else 2',
      'let x = 4 in x + 1', 'match [ 3 ] with | [] -> 0 | h :: t -> h'
    ];
    for (expr in expressions) {
      // Syntax values stay at the adapter boundaries only.
      var parsed = vm.parseWithNail(expr + ' ;');
      var sourceLiteral = Json.stringify(' ' + expr + ' ; ');
      var roundtrip = vm.run('let p = parseSource ' + sourceLiteral + ' in '
        + 'let e = head ( syntaxChildren ( head ( syntaxChildren p ) ) ) in '
        + 'match coreRead e with | CoreReadError m -> syntaxLeaf " Error " m '
        + '| CoreReadOk c -> coreToSyntax c ;')[0];
      var original:Value = switch (parsed) {
        case SyntaxNode('Program', Cons(SyntaxNode('Evaluate', Cons(e, Nil)), Nil)): e;
        case _: throw 'Unexpected parsed expression';
      };
      check(same(original, roundtrip), 'lossless expression roundtrip: ' + expr);
      check(same(vm.compileWithNail(expr + ' ;'), BytecodeCompiler.compileSource(expr + ' ;')),
        'bytecode equality: ' + expr);
    }
    var malformed = [
      'syntaxNode " Apply " []', 'syntaxNode " Lambda " []',
      'syntaxNode " If " []', 'syntaxNode " Literal " []',
      'syntaxLeaf " Unknown " " x "',
      'syntaxNode " Literal " [ syntaxLeaf " Bool " " maybe " ]',
      'syntaxNode " Apply " [ syntaxLeaf " Var " " x " , syntaxNode " Bad " [] ]'
    ];
    for (input in malformed) {
      var result = vm.runPlain('match coreRead ( ' + input + ' ) with '
        + '| CoreReadOk c -> false | CoreReadError m -> true ;');
      check(Json.stringify(result) == '[true]', 'malformed adapter input rejected: ' + input);
    }
    rejects(() -> new ByteVm().run(vm.run('syntaxNode " Bytecode " [ bcInstruction1 " EVAL " '
      + '( bcCode ( compileTail ( syntaxNode " Bad " [] ) ) ) ] ;')[0]), 'Invalid bytecode instruction');

    // Mixed user declarations still go through the same compiler boundary.
    var mixed = 'type Person { name Text age Number } ; type Option a = None | Some a ; '
      + 'def get p = match p with | None -> 0 | Some n -> n ; '
      + 'def person = Person " Ada " 32 ; get ( Some person . age ) ;';
    var compiled = vm.compileWithNail(mixed);
    check(same(compiled, BytecodeCompiler.compileSource(mixed)), 'records + sums bytecode equality');
    check(Json.stringify(new BootRuntime(100000000).runPlain(mixed)) == '[32]', 'records + sums boot result');

    // Recursive ADT traversal runs on VM frames, not the host call stack.
    var deep = 'def makeCore n acc = if n == 0 then acc else makeCore ( n - 1 ) ( CoreLambda " x " acc ) ; '
      + 'coreCompileTail ( makeCore 1200 ( CoreVar " x " ) ) ;';
    var deepOutput = boot.run(deep)[0];
    check(switch (deepOutput) { case Cons(_, _): true; case _: false; }, '1200-deep ADT compiler traversal');
    trace('NailSeed v0.20 core AST: ' + passed + ' tests passed');
  }
}
