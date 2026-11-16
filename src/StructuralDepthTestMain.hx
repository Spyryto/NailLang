import nail.Ast.Expr;
import nail.Ast.Form;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.Parser;
import nail.SyntaxBridge;
import nail.SyntaxEncoder;
import nail.TypeChecker;
import nail.Value;

/** v0.13: structural depth rather than call depth. All tests run on
    Haxe --interp, generated JS and generated PHP, against the same source. */
class StructuralDepthTestMain {
  static function assert(ok:Bool, label:String):Void {
    if (!ok) throw 'Structural depth failure: ' + label;
  }

  static function wrap(expr:Expr):Value return SyntaxEncoder.program([Evaluate(expr)]);

  static function decode(tree:Value):Expr {
    var forms = SyntaxBridge.forms(tree);
    if (forms.length != 1) throw 'Wrong form count';
    return switch (forms[0]) {
      case Evaluate(expr): expr;
      case _: throw 'Expected evaluation form';
    };
  }

  static function main():Void {
    var tests = 0;

    // 7,000 nested lambdas stress encoder and bridge without executing the tree.
    var nested:Expr = Var('end');
    for (i in 0...7000) nested = Lambda('a', nested);
    var rebuilt = decode(wrap(nested));
    var depth = 0;
    var inspecting = true;
    while (inspecting) switch (rebuilt) {
      case Lambda(_, body): depth++; rebuilt = body;
      case Var('end'): inspecting = false;
      case _: throw 'Wrong structural round-trip';
    }
    assert(depth == 7000, 'deep lambda round-trip');
    tests++;

    // 6,000 nested conditions have a constant scalar type but stress
    // expression inference and the reference compiler's BRANCH lowering.
    var condition:Expr = Literal(Number(1));
    for (i in 0...6000)
      condition = If(Literal(Boolean(true)), condition, Literal(Number(0)));
    var syntax = wrap(condition);
    var inferred = new TypeChecker().checkSyntax(syntax);
    assert(inferred.length == 1 && inferred[0] == 'Number', 'deep type inference');
    tests++;
    var result = new ByteVm(250000).run(BytecodeCompiler.compileSyntax(syntax));
    assert(result.length == 1, 'deep bytecode result count');
    switch (result[0]) {
      case Number(n): assert(n == 1, 'deep bytecode output');
      case _: throw 'Unexpected bytecode result';
    }
    tests++;

    // Separate deep application chain checks general source-level inference
    // with no source-parser recursion or host closure calls.
    var applied:Expr = Literal(Number(3));
    for (i in 0...3500) applied = Apply(Var('id'), applied);
    var checker = new TypeChecker();
    checker.check('def id x = x ;');
    assert(checker.checkSyntax(wrap(applied))[0] == 'Number', 'deep application inference');
    tests++;
    var code = BytecodeCompiler.compile([Define('id', Lambda('x', Var('x'))), Evaluate(applied)]);
    var byteResult = new ByteVm(100000).run(code);
    switch (byteResult[0]) {
      case Number(n): assert(n == 3, 'deep apply bytecode');
      case _: throw 'Bad application bytecode value';
    }
    tests++;

    // Error handling is still precise for malformed tree leaves at depth.
    var invalid:Value = SyntaxLeaf('Error', 'intentional-error');
    for (i in 0...5000) {
      var pair:Value = Cons(SyntaxLeaf('Name', 'x'), Cons(invalid, Nil));
      invalid = SyntaxNode('Lambda', pair);
    }
    var invalidProgram:Value = SyntaxNode('Program',
      Cons(SyntaxNode('Evaluate', Cons(invalid, Nil)), Nil));
    var rejected = false;
    try SyntaxBridge.forms(invalidProgram) catch (e:Dynamic) {
      rejected = Std.string(e).indexOf('intentional-error') >= 0;
    }
    assert(rejected, 'deep invalid syntax error');
    tests++;

    // Repeated redundant parentheses are a common accidental parser hazard.
    var source = new StringBuf();
    for (i in 0...7000) source.add(' ( ');
    source.add(' 42 ');
    for (i in 0...7000) source.add(' ) ');
    source.add(' ;');
    var grouped = new Parser(source.toString()).parse();
    assert(grouped.length == 1, 'deep grouping parsed');
    switch (grouped[0]) {
      case Evaluate(Literal(Number(n))): assert(n == 42, 'deep grouping value');
      case _: throw 'Deep grouping parsed incorrectly';
    }
    tests++;

    trace('NailSeed v0.13: ' + tests + ' structural-depth tests passed');
  }
}
