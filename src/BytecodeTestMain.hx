import haxe.Json;
import haxe.Resource;
import nail.Ast.Expr;
import nail.Ast.Form;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.Value;
import nail.Vm;
import nail.SyntaxBridge;
import nail.SyntaxEncoder;
import nail.Parser;

/** Tests for the Nail compiler against independent Haxe compilation and execution. */
class BytecodeTestMain {
  static function compare(vm:Vm, source:String, expected:String):Void {
    var syntax = vm.parseWithNail(source);
    // The Nail tokenizer still uses host-recursive character scanning;
    // large test inputs use the Haxe bootstrap parser and Nail's compiler.
    var fromNail = source.length > 110
      ? vm.compileSyntaxWithNail(SyntaxEncoder.program(new Parser(source).parse()))
      : vm.compileWithNail(source);
    var fromHaxe = BytecodeCompiler.compileSyntax(syntax);
    var got = Json.stringify(Vm.toPlain(fromNail));
    var ref = Json.stringify(Vm.toPlain(fromHaxe));
    if (got != ref) throw 'Bytecode mismatch for ' + source + '\nNail ' + got + '\nHaxe ' + ref;
    var compiled = new ByteVm(10000000);
    var result = Json.stringify(compiled.runPlain(fromNail));
    if (result != expected) throw 'Wrong bytecode result for ' + source + '\nExpected ' + expected + '\nGot ' + result;
    var ast = new Vm(10000000);
    var referenceResult = Json.stringify(ast.runPlain(source));
    if (result != referenceResult) throw 'AST and bytecode execution disagree for ' + source;
  }

  static function badBytecode(input:Value, pattern:String):Void {
    try {
      new ByteVm(10000).run(input);
      throw 'Invalid bytecode accepted';
    } catch (e:Dynamic) {
      if (Std.string(e).indexOf(pattern) < 0) throw 'Wrong error ' + Std.string(e) + ', expected ' + pattern;
    }
  }

  static function list(values:Array<Value>):Value {
    var result:Value = Nil;
    var i = values.length;
    while (i > 0) { i--; result = Cons(values[i], result); }
    return result;
  }
  static function leaf(tag:String, text:String):Value return SyntaxLeaf(tag, text);
  static function node(tag:String, parts:Array<Value>):Value return SyntaxNode(tag, list(parts));

  static function main():Void {
    var compiler = new Vm(15000000);
    compiler.loadStdlib();
    var examples = [
      {code: '2 + 3 ;', expected: '[5]'},
      {code: '2 * 4 + 1 ;', expected: '[9]'},
      {code: 'true ; false ;', expected: '[true,false]'},
      {code: 'if true then 3 else 1 / 0 ;', expected: '[3]'},
      {code: 'if false then 1 / 0 else 8 ;', expected: '[8]'},
      {code: 'def twice x = x * 2 ; twice 9 ;', expected: '[18]'},
      {code: 'def add a b = a + b ; add 2 7 ;', expected: '[9]'},
      {code: 'def add a b = a + b ; def inc = add 1 ; inc 10 ;', expected: '[11]'},
      {code: 'def square x = x * x ; def fourth x = square ( square x ) ; fourth 3 ;', expected: '[81]'},
      {code: 'def fact n = if n < 2 then 1 else n * fact ( n - 1 ) ; fact 6 ;', expected: '[720]'},
      {code: 'let x = 4 in x + 3 ;', expected: '[7]'},
      {code: 'def adder x = fun y -> x + y ; adder 10 5 ;', expected: '[15]'},
      {code: 'def make f = fun x -> f ( f x ) ; make ( fun x -> x + 1 ) 6 ;', expected: '[8]'},
      {code: '" hello world " ;', expected: '["hello world"]'},
      {code: '" hi " == " hi " ;', expected: '[true]'},
      {code: '[ 1 , 2 , 3 ] ;', expected: '[[1,2,3]]'},
      {code: 'head ( tail [ 3 , 4 ] ) ;', expected: '[4]'},
      {code: 'match [ 2 , 3 ] with | [] -> 0 | h :: t -> h ;', expected: '[2]'},
      {code: 'match [] with | [] -> 42 | h :: t -> h ;', expected: '[42]'},
      {code: 'def sum xs = match xs with | [] -> 0 | h :: t -> h + sum t ; sum [ 1 , 2 , 3 ] ;', expected: '[6]'},
      {code: 'let f = fun xs -> match xs with | [] -> false | h :: t -> h in f [ true ] ;', expected: '[true]'},
      {code: 'def f x = if x then " yes " else " no " ; f false ;', expected: '["no"]'},
      {code: '1 ; 2 ; 3 ;', expected: '[1,2,3]'},
      {code: 'def f x = let y = x + 1 in y * y ; f 4 ;', expected: '[25]'},
      {code: 'def loop n acc = if n == 0 then acc else loop ( n - 1 ) ( acc + 1 ) ; loop 6 0 ;', expected: '[6]'},
      {code: 'def tailLet x = let y = x + 1 in y ; tailLet 5 ;', expected: '[6]'},
      {code: 'def outer x = let f = fun y -> y + x in f 3 ; outer 7 ;', expected: '[10]'},
      {code: 'def tricky n = 10 + ( if n == 0 then 2 else 3 ) ; tricky 1 ;', expected: '[13]'}
    ];
    for (item in examples) compare(compiler, item.code, item.expected);

    // Invalid bytecode is rejected before it can silently change semantics.
    var invalid = [
      {value: node('Bad', []), message: 'expected Bytecode'},
      {value: node('Bytecode', [node('EVAL', [node('Code', [node('CALL', [])])])]), message: 'underflow'},
      {value: node('Bytecode', [node('EVAL', [node('Code', [node('CONST', [])])])]), message: 'arity'},
      {value: node('Bytecode', [node('EVAL', [node('Code', [node('NONSENSE', [])])])]), message: 'Unknown opcode'},
      {value: node('Bytecode', [node('EVAL', [node('Code', [node('CONST', [node('Literal', [leaf('Bool','true')])])])])]), message: 'missing RETURN'},
      {value: node('Bytecode', [node('EVAL', [node('Code', [node('TAIL_CALL', []), node('RETURN', [])])])]), message: 'TAIL_CALL outside tail position'},
      {value: node('Bytecode', [node('EVAL', [node('Code', [node('CONST', [node('Literal', [leaf('Bool','true')])]), node('RETURN', []), node('RETURN', [])])])]), message: 'instructions after RETURN'}
    ];
    for (item in invalid) badBytecode(item.value, item.message);

    // Limited compiler bootstrap: compile the 14 compiler definitions
    // (including compileExpr itself) to bytecode using Nail, load them
    // in ByteVm, then have that compiled compiler generate another program.
    // Haxe supplies the initial Syntax AST, not the emitted instructions.
    var libraryText = Resource.getString('stdlib');
    var compilerNames = [
      'append', 'bcCode', 'bcInstruction0', 'bcInstruction1',
      'bcInstruction2', 'bcReturn', 'bcCall', 'bcTailCall', 'compileGo', 'compileExpr', 'compileTail',
      'compileForm', 'compileForms', 'compileSyntax'
    ];
    var boot = new ByteVm(15000000);
    for (form in new Parser(libraryText).parse()) {
      switch (form) {
        case Define(name, _) if (compilerNames.indexOf(name) >= 0):
          var single = SyntaxEncoder.program([form]);
          boot.run(compiler.compileSyntaxWithNail(single));
        case _:
      }
    }
    for (name in compilerNames) if (boot.names().indexOf(name) < 0)
      throw 'Missing bootstrapped compiler definition ' + name;
    var input = 'def twice x = x * 2 ; twice 7 ;';
    var inputTree = SyntaxEncoder.program(new Parser(input).parse());
    var compilerOutput = boot.compileSyntax(inputTree);
    var referenceOutput = BytecodeCompiler.compileSource(input);
    if (Json.stringify(Vm.toPlain(compilerOutput)) != Json.stringify(Vm.toPlain(referenceOutput)))
      throw 'Bytecode compiler self-bootstrap disagrees with Haxe reference';
    if (Json.stringify((new ByteVm(100000)).runPlain(compilerOutput)) != '[14]')
      throw 'Bootstrapped compiler result incorrect';

    // Deep tail recursion is the regression that v0.10 could not survive.
    // Deliberately avoid recursively interpreting the source with Vm: the
    // optimization belongs to ByteVm, not the AST interpreter yet.
    var deepSource = 'def loop n acc = if n == 0 then acc else loop ( n - 1 ) ( acc + 1 ) ; loop 30000 0 ;';
    var deepNail = compiler.compileWithNail(deepSource);
    var deepHaxe = BytecodeCompiler.compileSource(deepSource);
    if (Json.stringify(Vm.toPlain(deepNail)) != Json.stringify(Vm.toPlain(deepHaxe)))
      throw 'Deep recursion program bytecode mismatch';
    var bytecodeJson = Json.stringify(Vm.toPlain(deepNail));
    if (bytecodeJson.indexOf('TAIL_CALL') < 0) throw 'Missing TAIL_CALL opcode';
    if (Json.stringify(new ByteVm(5000000).runPlain(deepNail)) != '[30000]')
      throw 'Tail-call trampoline failed at depth 30000';

    // Tail position is preserved across mutually recursive definitions.
    var mutualSource = 'def even n = if n == 0 then true else odd ( n - 1 ) ; '
      + 'def odd n = if n == 0 then false else even ( n - 1 ) ; even 20000 ;';
    var mutual = BytecodeCompiler.compileSource(mutualSource);
    if (Json.stringify(new ByteVm(3000000).runPlain(mutual)) != '[true]')
      throw 'Mutual tail recursion failed at depth 20000';

    try {
      new ByteVm(200).run(deepNail);
      throw 'Execution budget wrongly allowed unbounded tail recursion';
    } catch (e:Dynamic) {
      if (Std.string(e).indexOf('execution budget exceeded') < 0)
        throw 'Unexpected execution-budget result: ' + Std.string(e);
    }

    var fail = compiler.compileWithNail('if ;');
    try {
      new ByteVm().run(fail);
      throw 'Parser error accepted as bytecode';
    } catch (e:Dynamic) {
      if (Std.string(e) == 'Parser error accepted as bytecode') throw e;
    }
    trace('NailSeed v0.11: ' + (examples.length + invalid.length + 6) + ' bytecode/TCO tests passed');
  }
}
