import haxe.Json;
import nail.Value;
import nail.Ast.Form;
import nail.Parser;
import nail.Vm;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.ByteVm;
import nail.SyntaxEncoder;
import nail.SyntaxBridge;
import nail.RecordLowering;
import nail.SumLowering;
import nail.TypeChecker;

/** The production compiler lowers records and sums in Nail, then compiles
    only ordinary definitions and evaluations. Haxe remains a separate seed
    and reference oracle; the source-free boot image must agree exactly. */
class TypeDeclarationLoweringTestMain {
  static var checks = 0;
  static function ok(value:Bool, name:String):Void {
    if (!value) throw 'TYPE DECLARATION LOWERING: ' + name;
    checks++;
  }
  static function equal(a:Value, b:Value, name:String):Void
    ok(BootstrapImage.encode(a) == BootstrapImage.encode(b), name);

  static function oracle(source:String):Value {
    var result:Array<Form> = [];
    for (form in new Parser(source).parse()) switch (form) {
      case RecordType(name, _, fields):
        for (generated in RecordLowering.definitions(name, fields)) result.push(generated);
      case SumType(name, _, constructors):
        for (generated in SumLowering.definitions(name, constructors)) result.push(generated);
      case _:
        result.push(form);
    }
    return SyntaxEncoder.program(result);
  }

  public static function main():Void {
    var host = new Vm(60000000);
    host.loadStdlib();
    var cases = [
      {source:'', result:'[]'},
      {source:'def localIdentity x = x ; localIdentity 42 ;', result:'[42]'},
      {source:'type Person { age Number } ; ( Person 42 ) . age ;', result:'[42]'},
      {source:'type Option a = None | Some a ; match Some 42 with | None -> 0 | Some x -> x ;',
        result:'[42]'},
      {source:'type Choice = Left Number | Right Number ; match Right 42 with | Left x -> 0 | Right y -> y ;',
        result:'[42]'},
      {source:'type Box { value Number } ; type Option a = None | Some a ; match Some ( Box 42 ) with | None -> 0 | Some b -> b . value ;',
        result:'[42]'},
      {source:'type Choice = Empty | Full Number ; type Box { value Number } ; match Full ( ( Box 42 ) . value ) with | Empty -> 0 | Full n -> n ;',
        result:'[42]'},
      {source:'macro wrap n = quote ( Box ( unquote n ) ) ; type Box { value Number } ; ( expand wrap 42 ) . value ;',
        result:'[42]'},
      {source:'nail 0.49 ; type Box { value Int } ; type Choice = No | Yes Int ; match Yes ( ( Box 42 ) . value ) with | No -> 0 | Yes n -> n ;',
        result:'["I:42"]'}
    ];
    for (entry in cases) {
      // Each executable program has its own top-level namespace.
      var boot = new BootRuntime(60000000);
      var source = entry.source;
      var referenceSource = SyntaxEncoder.program(new Parser(source).parse());
      var generated = oracle(source);
      var fromHost = host.invoke('expandTypeDeclarations', host.parseWithNail(source));
      var fromBoot = boot.invoke('expandTypeDeclarations', referenceSource);

      equal(fromHost, generated, 'Nail lowering agrees with independent Haxe lowering: ' + source);
      equal(fromBoot, generated, 'source-free lowering produces identical Syntax');
      equal(fromBoot, fromHost, 'source-free and Haxe-hosted Nail agree');
      for (form in SyntaxBridge.forms(fromHost)) switch (form) {
        case RecordType(_, _, _) | SumType(_, _, _):
          throw 'TYPE DECLARATION LOWERING: declaration survived lowering';
        case _:
      }

      // Type checking retains the *source* declarations; compilation uses
      // only the generated definitions (no nominal type erasure in the checker).
      new TypeChecker().check(source);
      var expected = BytecodeCompiler.compileSource(source);
      equal(expected, BytecodeCompiler.compile(SyntaxBridge.forms(fromHost)),
        'ordinary Haxe compilation of lowered forms matches reference');
      equal(expected, host.compileWithNail(source), 'Nail compiler matches reference');
      equal(expected, boot.compile(source), 'source-free Nail compiler matches reference');

      var actual = Json.stringify(boot.runPlain(source));
      ok(actual == entry.result,
        'source-free execution: ' + source + ' expected ' + entry.result + ', got ' + actual);
      ok(Json.stringify(new ByteVm(60000000).runPlain(expected)) == actual,
        'reference bytecode execution matches source-free execution');
    }
    trace('Unified Nail declaration lowering: ' + checks + ' checks passed');
  }
}
