import haxe.Json;
import haxe.Resource;
import nail.Ast.Form;
import nail.BytecodeCompiler;
import nail.ByteVm;
import nail.Parser;
import nail.SyntaxEncoder;
import nail.Value;
import nail.Vm;

/** v0.12 regression: neither AST evaluation nor the bytecode bootstrap may
    rely on recursive Haxe/JS/PHP calls, even for non-tail source recursion. */
class BootstrapDepthTestMain {
  static function check(actual:String, expected:String, description:String):Void {
    if (actual != expected) throw description + ': expected ' + expected + ', got ' + actual;
  }

  static function repeat(text:String, times:Int):String {
    var result = new StringBuf();
    for (_ in 0...times) result.add(text);
    return result.toString();
  }

  static function bootstrap(compiler:Vm):ByteVm {
    var selected = [
      'append', 'bcCode', 'bcInstruction0', 'bcInstruction1',
      'bcInstruction2', 'bcReturn', 'bcCall', 'bcTailCall',
      'compileGo', 'compileExpr', 'compileTail', 'compileForm',
      'compileForms', 'compileSyntax'
    ];
    var vm = new ByteVm(25000000);
    for (form in new Parser(Resource.getString('stdlib')).parse()) {
      switch (form) {
        case Define(name, _) if (selected.indexOf(name) >= 0):
          vm.run(compiler.compileSyntaxWithNail(SyntaxEncoder.program([form])));
        case _:
      }
    }
    for (name in selected)
      if (vm.names().indexOf(name) < 0) throw 'Missing bootstrap definition: ' + name;
    return vm;
  }

  static function main():Void {
    var ast = new Vm(30000000);
    ast.loadStdlib();
    var tests = 0;

    // A small program with thousands of preceding spaces forces thousands
    // of tail calls in Nail's tokenizer before parsing one expression.
    var padded = repeat(' ', 5200) + ' 1 ; ';
    check(Json.stringify(ast.runPlainWithNail(padded)), '[1]', 'Deep self-tokenization and self-parser');
    tests++;
    var compiled = ast.compileWithNail(padded);
    check(Json.stringify(new ByteVm(300000).runPlain(compiled)), '[1]', 'Self-parser + Nail compiler + ByteVm');
    tests++;

    // The source evaluator now supports non-tail recursion without recursive
    // host calls, using explicit continuation frames on the managed heap.
    var nonTail = 'def count n = if n == 0 then 0 else 1 + count ( n - 1 ) ; count 8500 ;';
    check(Json.stringify(ast.runPlain(nonTail)), '[8500]', 'Deep non-tail AST recursion');
    tests++;
    var nonTailCode = BytecodeCompiler.compileSource(nonTail);
    check(Json.stringify(new ByteVm(2500000).runPlain(nonTailCode)), '[8500]', 'Deep non-tail bytecode recursion');
    tests++;

    // Deep mutual tail recursion is still constant in VM call-stack space.
    var mutual = 'def even n = if n == 0 then true else odd ( n - 1 ) ; '
      + 'def odd n = if n == 0 then false else even ( n - 1 ) ; even 12000 ;';
    check(Json.stringify(ast.runPlain(mutual)), '[true]', 'Deep mutual AST recursion');
    tests++;
    check(Json.stringify(new ByteVm(2500000).runPlain(BytecodeCompiler.compileSource(mutual))), '[true]', 'Deep mutual bytecode recursion');
    tests++;

    // Compiler's list traversal is non-tail: it should use managed frames,
    // not one PHP/JS/Haxe call-stack frame per source declaration.
    var bulkSource = repeat('1 ; ', 1700);
    var bulkTree = SyntaxEncoder.program(new Parser(bulkSource).parse());
    var nailCode = ast.compileSyntaxWithNail(bulkTree);
    check(Std.string(new ByteVm(1000000).run(nailCode).length), '1700', 'Bulk Nail source compiler');
    tests++;
    var compiledCompiler = bootstrap(ast);
    var byteCompiled = compiledCompiler.compileSyntax(bulkTree);
    check(Std.string(new ByteVm(1000000).run(byteCompiled).length), '1700', 'Bytecode-bootstrapped compiler on bulk source');
    tests++;

    // The interpreter must still be interruptible with a deterministic
    // instruction budget: no unbounded looping because of the trampoline.
    try {
      var guarded = new Vm(300);
      guarded.run('def loop n = loop n ; loop 1 ;');
      throw 'AST execution budget not enforced';
    } catch (e:Dynamic) {
      if (Std.string(e).indexOf('Execution budget exceeded') < 0) throw e;
    }
    tests++;
    try {
      new ByteVm(300).run(nonTailCode);
      throw 'Bytecode execution budget not enforced';
    } catch (e:Dynamic) {
      if (Std.string(e).indexOf('execution budget exceeded') < 0) throw e;
    }
    tests++;

    trace('NailSeed v0.12: ' + tests + ' iterative bootstrap/depth tests passed');
  }
}
