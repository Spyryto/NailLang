package nail;

import nail.Ast.Form;
import nail.NType;
import nail.SourcePositions.SourceSpan;
import nail.Value;

/** Public opt-in execution boundary for transformers authored as ordinary
    Nail functions: (Syntax -> Syntax). The transformer returns a Program
    containing only NEW definitions; a typed, transactional host contract
    validates every generated body before it can be compiled.

    The host VM and source-free bootstrap are two interchangeable execution
    backends, both with ordinary Nail primitives and execution budgets.
    No arbitrary host callbacks, I/O privileges or compile-time eval are
    granted to the transformer. */
class ProceduralTransformer {
  static var standardTypes:Null<TypeChecker> = null;

  static function checkEntry(source:String, name:String):Void {
    if (!~/^[A-Za-z_][A-Za-z_0-9]*$/.match(name))
      throw 'Procedural transformer: invalid entry name';
    // Existing Nail Syntax builders (syntaxDefine, syntaxLambda, syntaxApply,
    // etc.) are part of the *Nail-written* stdlib, not new native primitives.
    // Resolve their inferred signatures once, without making any library
    // definitions global in the caller's mutable checker instance.
    if (standardTypes == null) {
      var base = new TypeChecker();
      var library = haxe.Resource.getString('stdlib');
      if (library != null) base.check(library);
      standardTypes = base;
    }
    var checker = standardTypes.copy();
    checker.check(source);
    if (checker.signature(name) != 'Syntax -> Syntax')
      throw 'Procedural transformer: ' + name + ' must have signature Syntax -> Syntax';
  }

  static function validate(source:Value, raw:Value,
      contracts:Array<{name:String, type:NType}>, ?site:SourceSpan):Value {
    // Hygiene rewrites only local markers deliberately introduced by the
    // generator. It never renames free caller syntax. Validation then checks
    // all generated declarations against closed explicit type signatures.
    var cleaned:Value;
    try {
      cleaned = ProceduralHygiene.prepare(raw);
      ProceduralHygiene.verifyPrepared(cleaned);
    } catch (error:Dynamic) {
      if (site == null) throw error;
      throw 'Procedural transformer at ' + site.line + ':'
        + site.column + ': ' + Std.string(error);
    }
    return GeneratedDeclarationValidator.validateTyped(source, cleaned, contracts, site);
  }

  public static function generateHost(source:Value, transformerSource:String,
      entry:String, contracts:Array<{name:String, type:NType}>,
      ?site:SourceSpan, maxSteps:Int = 1000000):Value {
    checkEntry(transformerSource, entry);
    var vm = new Vm(maxSteps);
    vm.loadStdlib();
    vm.run(transformerSource);
    return validate(source, vm.invoke(entry, source), contracts, site);
  }

  /** Same public contract, executed via a parser-free Nail bootstrap image.
      Loading user code is compiled by the Nail-written compiler, not by
      Haxe's Parser. */
  public static function generateBoot(source:Value, transformerSource:String,
      entry:String, contracts:Array<{name:String, type:NType}>,
      ?site:SourceSpan, maxSteps:Int = 25000000):Value {
    checkEntry(transformerSource, entry);
    var boot = new BootRuntime(maxSteps);
    boot.run(transformerSource);
    return validate(source, boot.invoke(entry, source), contracts, site);
  }

  /** Append the already verified fresh definitions to the original Program.
      Only this public compilation entry point accepts generated declarations. */
  public static function compile(source:Value, generated:Value,
      contracts:Array<{name:String, type:NType}>):Value {
    // Repeat type checking rather than trusting a previously prepared tree:
    // Haxe callers can construct or modify arbitrary Syntax values.
    ProceduralHygiene.verifyPrepared(generated);
    GeneratedDeclarationValidator.validateTyped(source, generated, contracts);
    return BytecodeCompiler.compileSyntax(combine(source, generated));
  }

  public static function combine(source:Value, generated:Value):Value {
    var forms:Array<Form> = SyntaxBridge.forms(source);
    var emitted:Array<Form> = SyntaxBridge.forms(generated);
    for (item in emitted) switch (item) {
      case Define(_, _):
      case _: throw 'Procedural transformer: only new definitions can be appended';
    }
    return SyntaxEncoder.program(forms.concat(emitted));
  }
}
