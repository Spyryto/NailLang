package nail;

import nail.Ast.Form;
import nail.Value;
import nail.NType;
import nail.SourcePositions.SourceSpan;

/** Validate a trusted Nail record transformation against source signatures
    and an independent Haxe lowering. This is intentionally a closed contract:
    it does not claim to type-check arbitrary user-generated Syntax. */
class GeneratedDeclarationValidator {
  /** Open, typed declaration contract (no runtime primitive privileges).
      Generated top-level functions are checked against explicit monomorphic
      signatures in a source-validated environment. The immutable generated
      Program is returned unchanged on success. The optional call site is
      diagnostic-only and cannot affect successful compilation. */
  public static function validateTyped(source:Value, generated:Value,
      contracts:Array<{name:String, type:NType}>, ?callSite:SourceSpan):Value {
    try {
      new TypeChecker().checkGenerated(source, generated, contracts);
    } catch (error:Dynamic) {
      if (callSite == null) throw error;
      throw 'Generated declaration at ' + callSite.line + ':'
        + callSite.column + ': ' + Std.string(error);
    }
    return generated;
  }

  public static function validate(plan:Value, ?checker:TypeChecker):Value {
    var source:Value;
    var runtime:Value;
    switch (plan) {
      case SyntaxNode('RecordExpansion', Cons(a, Cons(b, Nil))):
        source = a;
        runtime = b;
      case _: throw 'Invalid generated declaration contract: expected RecordExpansion';
    }

    // Parsing arbitrary generated Syntax goes through the usual structural
    // validator; the original nominal declarations still drive type checking.
    var original = SyntaxBridge.forms(source);
    var actual = SyntaxBridge.forms(runtime);
    if (checker == null) checker = new TypeChecker();
    checker.checkSyntax(source);

    var expected:Array<Form> = [];
    var owners:Array<String> = [];
    for (form in original) switch (form) {
      case RecordType(name, _, fields):
        var definitions = RecordLowering.definitions(name, fields);
        for (definition in definitions) {
          expected.push(definition);
          owners.push(name);
        }
      case _:
        expected.push(form);
        owners.push('source');
    }

    if (actual.length != expected.length)
      throw 'Invalid generated declaration contract: form count (expected '
        + expected.length + ', got ' + actual.length + ')';

    // Compare the exact generated Syntax AST rather than just names or
    // arities: a malformed getter could otherwise lie about its signature.
    // Both programs are decoded to the same five-constructor core.
    for (i in 0...expected.length) {
      var emitted = BootstrapImage.encode(SyntaxEncoder.form(actual[i]));
      var reference = BootstrapImage.encode(SyntaxEncoder.form(expected[i]));
      if (emitted != reference)
        throw 'Invalid generated declaration contract: mismatch at form '
          + i + ' (' + owners[i] + ')';
    }
    return runtime;
  }
}
