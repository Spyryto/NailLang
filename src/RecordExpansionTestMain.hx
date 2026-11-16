import haxe.Json;
import nail.Value;
import nail.Vm;
import nail.ByteVm;
import nail.Parser;
import nail.SyntaxBridge;
import nail.SyntaxEncoder;
import nail.RecordLowering;
import nail.BytecodeCompiler;
import nail.BootstrapImage;
import nail.BootRuntime;
import nail.TypeChecker;
import nail.Ast.Form;

/** The transformer runs as Nail code; the Haxe lowering is an independent oracle. */
class RecordExpansionTestMain {
  static var passed = 0;
  static function ok(condition:Bool, message:String):Void {
    if (!condition) throw 'RECORD EXPANSION: ' + message;
    passed++;
  }
  static function same(a:Value, b:Value, message:String):Void
    ok(BootstrapImage.encode(a) == BootstrapImage.encode(b), message);
  static function parts(plan:Value):Array<Value> return switch plan {
    case SyntaxNode('RecordExpansion', Cons(source, Cons(runtime, Nil))): [source, runtime];
    case _: throw 'Expected RecordExpansion with two Programs';
  };
  static function fails(fn:Void->Void, phrase:String):Void {
    var message = '';
    try fn() catch (e:Dynamic) message = Std.string(e);
    ok(message.indexOf(phrase) >= 0, 'expected ' + phrase + ', got ' + message);
  }
  static function oracle(source:String):Value {
    var out:Array<Form> = [];
    for (form in new Parser(source).parse()) switch form {
      case RecordType(name, _, fields): for (definition in RecordLowering.definitions(name, fields)) out.push(definition);
      case _: out.push(form);
    }
    return SyntaxEncoder.program(out);
  }
  public static function main():Void {
    var host = new Vm(50000000);
    host.loadStdlib();
    var wide = 'type Wide { ';
    for (i in 0...128) wide += 'f' + i + ' Number ';
    wide += '} ;';
    var cases = [
      '',
      'def id x = x ; id 7 ;',
      'type Person { name Text age Number } ; def p = Person " Ada " 32 ; p . name ;',
      'type Person { name Text } ; type Badge { owner Person valid Bool } ; ( Badge ( Person " Ada " ) true ) . owner . name ;',
      'type A { value Number } ; type B { value Text } ; ( B " yes " ) . value ;',
      'def x = 8 ; type Edge { cons Number recordAccessor Text } ; ( Edge x " safe " ) . cons ;',
      'type Option a = None | Some a ; type Box { value Number } ; match Some ( Box 42 ) with | None -> 0 | Some x -> x . value ;',
      wide
    ];
    for (source in cases) {
      var plan = parts(host.expandRecordsWithNail(source));
      same(plan[0], SyntaxEncoder.program(new Parser(source).parse()), 'source declarations preserved');
      same(plan[1], oracle(source), 'Nail transformer equals independent Haxe lowering');
      for (form in SyntaxBridge.forms(plan[1])) switch form {
        case RecordType(_, _, _): throw 'record declaration survived transformation';
        case _:
      }
      var reference = BytecodeCompiler.compileSource(source);
      var transformed = BytecodeCompiler.compile(SyntaxBridge.forms(plan[1]));
      ok(BootstrapImage.encode(reference) == BootstrapImage.encode(transformed), 'ordinary forms compile identically');
      ok(BootstrapImage.encode(reference) == BootstrapImage.encode(host.compileWithNail(source)), 'Nail compiler uses transform pass');
      ok(Json.stringify(new ByteVm(50000000).runPlain(transformed)) == Json.stringify(new Vm(50000000).runPlain(source)), 'execution parity');
      same(parts(host.expandRecordsWithNail(source))[1], plan[1], 'deterministic expansion');
      new TypeChecker().checkSyntax(plan[0]);
      passed++;
    }
    var record = 'type Person { name Text age Number } ; ( Person " Ada " 32 ) . age ;';
    var plan = parts(host.expandRecordsWithNail(record));
    var checker = new TypeChecker();
    ok(Json.stringify(checker.checkSyntax(plan[0])) == '["Number"]', 'nominal result type retained');
    ok(checker.signature('Person.name') == 'Person -> Text', 'qualified getter type retained');
    fails(() -> new TypeChecker().checkSyntax(parts(host.expandRecordsWithNail('type Bad { x Missing } ;'))[0]), 'unknown record field type');
    fails(() -> new TypeChecker().checkSyntax(parts(host.expandRecordsWithNail('type T { x Number } ; T true ;'))[0]), 'cannot unify');
    var bad = host.expandRecordsWithNail('type Empty { } ;');
    ok(switch bad { case SyntaxLeaf('Error', message): message.indexOf('Record requires') >= 0; case _: false; }, 'parser error is propagated');
    var invalid = host.expandRecordsWithNail('type T { x Number x Text } ;');
    ok(switch invalid { case SyntaxLeaf('Error', message): message.indexOf('Duplicate') >= 0; case _: false; }, 'duplicate field diagnostic retained');
    var macroSource = 'import make from records ; type T { x Number } ; ( expand make 12 ) . x ;';
    var modules = (name:String) -> name == 'records' ? 'macro make x = quote ( T ( unquote x ) ) ; export make ;' : null;
    var macroPlan = parts(host.expandRecordsWithNail(macroSource, modules));
    ok(Json.stringify(new TypeChecker().checkSyntax(macroPlan[0])) == '["Number"]', 'imported macro types survive');
    ok(Json.stringify(new ByteVm().runPlain(BytecodeCompiler.compile(SyntaxBridge.forms(macroPlan[1])))) == '[12]', 'imported macro and declaration expansion compose');
    var boot = new BootRuntime(50000000);
    ok(Json.stringify(boot.runPlain(record)) == '[32]', 'source-free compiler runs transformer');
    ok(Json.stringify(boot.runPlain('syntaxTag ( expandRecordDeclarations ( parseSource " type Probe { x Number } ; " ) ) ;')) == '["RecordExpansion"]', 'transformer is callable in precompiled Nail');
    trace('NailSeed v0.25 record expansion: ' + passed + ' passed');
  }
}
