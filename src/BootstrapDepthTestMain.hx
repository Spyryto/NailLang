import haxe.Json;
import haxe.Resource;
import nail.Ast.Form;
import nail.BytecodeCompiler;
import nail.ByteVm;
import nail.Parser;
import nail.SyntaxEncoder;
import nail.Value;
import nail.Vm;

/** Stress tests for source bootstrap and both iterative interpreters. */
class BootstrapDepthTestMain {
  static function check(actual:String, expected:String, what:String):Void {
    if (actual != expected) throw what + ': expected ' + expected + ', got ' + actual;
  }
  static function repeat(text:String, count:Int):String {
    var result = new StringBuf();
    for (_ in 0...count) result.add(text);
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
    for (name in selected) if (vm.names().indexOf(name) < 0)
      throw 'Missing bootstrap definition: ' + name;
    return vm;
  }
  static function main():Void {
    var ast = new Vm(30000000);
    ast.loadStdlib();
    var tests = 0;
    var padded = repeat(' ', 5200) + ' 1 ; ';
    check(Json.stringify(ast.runPlainWithNail(padded)), '[1]', 'Self-tokenizer/parser');
    tests++;
    check(Json.stringify(new ByteVm(300000).runPlain(ast.compileWithNail(padded))), '[1]', 'Self-compiled source');
    tests++;
    var nonTail = 'def count n = if n == 0 then 0 else 1 + count ( n - 1 ) ; count 8500 ;';
    check(Json.stringify(ast.runPlain(nonTail)), '[8500]', 'Non-tail AST recursion');
    tests++;
    var nonTailCode = BytecodeCompiler.compileSource(nonTail);
    check(Json.stringify(new ByteVm(2500000).runPlain(nonTailCode)), '[8500]', 'Non-tail ByteVM recursion');
    tests++;
    var mutual = 'def even n = if n == 0 then true else odd ( n - 1 ) ; '
      + 'def odd n = if n == 0 then false else even ( n - 1 ) ; even 12000 ;';
    check(Json.stringify(ast.runPlain(mutual)), '[true]', 'Mutual AST recursion');
    tests++;
    check(Json.stringify(new ByteVm(2500000).runPlain(BytecodeCompiler.compileSource(mutual))), '[true]', 'Mutual ByteVM recursion');
    tests++;
    var bulkTree = SyntaxEncoder.program(new Parser(repeat('1 ; ', 1700)).parse());
    var nailCode = ast.compileSyntaxWithNail(bulkTree);
    check(Std.string(new ByteVm(1000000).run(nailCode).length), '1700', 'Nail compiler on bulk source');
    tests++;
    var boot = bootstrap(ast);
    var byteCompiled = boot.compileSyntax(bulkTree);
    check(Std.string(new ByteVm(1000000).run(byteCompiled).length), '1700', 'Bytecode-bootstrapped compiler');
    tests++;
    try {
      new Vm(300).run('def loop n = loop n ; loop 1 ;');
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
