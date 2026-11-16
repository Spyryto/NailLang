import haxe.Json;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.Parser;
import nail.TypeChecker;
import nail.Vm;

/** v0.44: relation-constrained polymorphism only with explicit : Div. */
class ExplicitRelationsTestMain {
  static var passed = 0;
  static function ok(value:Bool, title:String):Void {
    if (!value) throw 'EXPLICIT DIV: ' + title;
    passed++;
  }
  static function same(actual:Dynamic,expected:Dynamic,title:String):Void
    ok(Json.stringify(actual) == Json.stringify(expected),
      title + ' expected='+Json.stringify(expected)+ ' actual='+Json.stringify(actual));

  static function fails(run:Void->Void,message:String):Void {
    var observed = '';
    try run() catch (e:Dynamic) observed = Std.string(e);
    ok(observed.indexOf(message)>=0,
      'expected "'+message+'" got "'+observed+'"');
  }

  public static function main():Void {
    // The same single implementation supports both *existing* domains:
    // Number (IEEE 754 Float) and Exact (arbitrary rational).
    // Int / Ratio / Float are the planned replacement, not yet shipped.
    var source = 'def divide x y : Div = x / y ; '
      + 'divide 9 2 ; '
      + 'divide ( exactFromText " 3 " ) ( exactFromText " 2 " ) ; ';
    var checker=new TypeChecker();
    same(checker.check(source),['Number','Exact'],
      'explicit Div allows concrete Float and exact overloads');
    ok(checker.signature('divide') == 'Div a b c => a -> b -> c',
      'type checker retains concise constrained signature');
    same(new Vm(40000000).runPlain(source),[4.5,'E:3/2'],
      'AST VM executes same function for both domains');
    var reference=BytecodeCompiler.compileSource(source);
    same(new ByteVm(40000000).runPlain(reference),[4.5,'E:3/2'],
      'reference bytecode executes both instances');
    var boot=new BootRuntime(40000000);
    var self=boot.compile(source);
    ok(BootstrapImage.encode(self)==BootstrapImage.encode(reference),
      'Nail-written parser/compiler erases : Div without bytecode drift');
    same(boot.runBytecode(self).map(Vm.toPlain),[4.5,'E:3/2'],
      'source-free bootstrap executes both overloads');

    // Relations are explicit, not silently inferred from '/' or Num.
    fails(() -> new TypeChecker().check(
      'def divide x y = x / y ; '
      + 'divide ( exactFromText " 3 " ) ( exactFromText " 2 " ) ;'),
      'cannot unify');
    fails(() -> new TypeChecker().check(
      'def divide x y : Div = x / y ; '
      + 'divide 3 ( exactFromText " 2 " ) ;'),
      'no Div instance');
    fails(() -> new TypeChecker().check(
      'def divide x y : Div = x + y ;'), 'cannot unify');
    fails(() -> new TypeChecker().check(
      'def divide x y : Div = x / y ; divide ;'),
      'requires two directly applied arguments');
    fails(() -> new TypeChecker().check(
      'def divide x y : Div = x / y ; divide 3 ;'),
      'requires two directly applied arguments');
    fails(() -> new TypeChecker().check(
      'def divide x y : Div = x / y ; '
      + 'def nested z = divide z z ;'), 'no Div instance');
    fails(() -> new Parser('def bad x : Div = x ;').parseRaw(),
      'only binary Div');
    fails(() -> new Parser('def bad x y : Mul = x * y ;').parseRaw(),
      'only binary Div');
    fails(() -> new Parser('macro bad x y : Div = x / y ;').parseRaw(),
      'only binary Div');
    fails(() -> new Parser('# nail: 0.29\ndef f x y : Div = x / y ;').parseRaw(),
      'exact source dialect is not supported yet');
    // No broad accidental "Num" subtype: just closed matching signatures.
    fails(() -> numeric.NumericRelation.result('Div',
      nail.NType.TText, nail.NType.TText), 'no Div instance');
    ok(numeric.NumericRelation.rows('Div').length == 2,
      'closed relation table contains two supported concrete signatures');


    // Successfully declared constraints persist across incremental checks.
    var incremental = new TypeChecker();
    incremental.check('def divide x y : Div = x / y ;');
    same(incremental.check('divide 8 4 ; '
      + 'divide ( exactFromText " 8 " ) ( exactFromText " 4 " ) ;'),
      ['Number','Exact'], 'incremental checker remembers Div relation');
    var copied = incremental.copy();
    same(copied.check('divide 5 2 ;'), ['Number'],
      'checker copy preserves relation declaration');
    fails(() -> incremental.check('def broken x y : Div = x + y ;'),
      'cannot unify');
    ok(incremental.names().indexOf('broken') < 0,
      'failed annotated batch is transactional');

    // Normal type inference still works and remains automatic.
    var again=new TypeChecker();
    again.check('def id x = x ;');
    ok(again.signature('id')=='a -> a',
      'unconstrained HM polymorphism unaffected');
    same(again.check('id true ; id 4 ;'),['Bool','Number'],
      'unconstrained polymorphic calls unaffected');
    trace('NailLang v0.44 explicitly constrained Div: '+passed+' checks passed');
  }
}
