import haxe.Json;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.TypeChecker;
import nail.Vm;

class MacroTestMain {
  static function check(ok:Bool, message:String):Void {
    if (!ok) throw message;
  }

  static function rejects(run:Void->Void, expected:String):Void {
    var message = '';
    try run() catch (e:Dynamic) message = Std.string(e);
    check(message.indexOf(expected) >= 0, 'Expected ' + expected + ', got ' + message);
  }

  static function agreement(source:String, expected:String, expectedTypes:String):Void {
    var vm = new Vm(25000000);
    vm.loadStdlib();
    var boot = new BootRuntime();
    check(Json.stringify(vm.runPlain(source)) == expected, 'host AST mismatch: ' + source);
    vm = new Vm(25000000);
    vm.loadStdlib();
    check(Json.stringify(vm.runPlainWithNail(source)) == expected, 'Nail AST mismatch: ' + source);
    var reference = BytecodeCompiler.compileSource(source);
    var self = vm.compileWithNail(source);
    check(BootstrapImage.encode(reference) == BootstrapImage.encode(self), 'compiler disagreement: ' + source);
    check(BootstrapImage.encode(self) == BootstrapImage.encode(boot.compile(source)), 'bootstrap disagreement');
    check(Json.stringify(boot.runPlain(source)) == expected, 'bootstrap output mismatch: ' + source);
    check(Json.stringify(new TypeChecker().check(source)) == expectedTypes, 'host checking mismatch: ' + source);
    check(Json.stringify(new TypeChecker().checkSyntax(vm.parseWithNail(source))) == expectedTypes,
      'Nail AST checking mismatch: ' + source);
  }

  static function main():Void {
    agreement('macro unless condition action = quote ( if unquote condition then 0 else unquote action ) ; '
      + 'expand unless true ( 1 / 0 ) ; expand unless false ( 40 + 2 ) ;',
      '[0,42]', '["Number","Number"]');
    agreement('macro save value = quote ( let tmp = 10 in tmp + unquote value ) ; '
      + 'let tmp = 32 in expand save tmp ;', '[42]', '["Number"]');
    agreement('def helper x = x + 1 ; macro increment x = quote ( helper ( unquote x ) ) ; '
      + 'let helper = true in expand increment 41 ;', '[42]', '["Number"]');
    agreement('macro addOne x = quote ( unquote x + 1 ) ; '
      + 'macro twice x = quote ( expand addOne ( expand addOne ( unquote x ) ) ) ; '
      + 'expand twice 40 ;', '[42]', '["Number"]');
    agreement('macro identity = quote ( fun x -> x ) ; macro ignored x = quote ( 42 ) ; '
      + 'expand identity 42 ; expand ignored ( 1 / 0 ) ;', '[42,42]', '["Number","Number"]');
    agreement('type Person { age Number } ; macro ageOf p = quote ( ( unquote p ) . age ) ; '
      + 'expand ageOf ( Person 42 ) ;', '[42]', '["Number"]');
    agreement('type Option a = None | Some a ; macro unwrap p = quote ( '
      + 'match unquote p with | None -> 0 | Some n -> n ) ; expand unwrap ( Some 42 ) ;',
      '[42]', '["Number"]');
    agreement('macro payload x = quote ( match [ unquote x ] with | [] -> 0 | h :: t -> h ) ; '
      + 'expand payload 42 ;', '[42]', '["Number"]');
    agreement('macro headName x = quote ( fun tmp -> unquote x ) ; '
      + 'let tmp = 42 in expand headName tmp false ;', '[42]', '["Number"]');
    agreement('macro recur x = quote ( loop ( unquote x ) ) ; '
      + 'def loop n = if n < 1 then 42 else expand recur ( n - 1 ) ; loop 2 ;', '[42]', '["Number"]');
    agreement('def gate x = true ; macro gate x = quote ( unquote x + 1 ) ; '
      + 'gate 0 ; expand gate 41 ;', '[true,42]', '["Bool","Number"]');

    agreement('" macro " ; " quote " ; " expand " ;',
      '["macro","quote","expand"]', '["Text","Text","Text"]');

    var boot = new BootRuntime();
    var vm = new Vm(25000000);
    vm.loadStdlib();
    for (entry in [
      {source:'expand missing 1 ;', error:'unknown macro missing'},
      {source:'macro m x = quote ( unquote x ) ; expand m ;', error:'expects 1 arguments'},
      {source:'macro m x = quote ( unquote typo ) ;', error:'unknown unquote parameter'},
      {source:'macro m = quote ( 1 ) ; macro m = quote ( 2 ) ;', error:'duplicate macro'},
      {source:'macro m = 1 ;', error:'expected quote'},
      {source:'unquote x ;', error:'unquote belongs inside'},
      {source:'macro m = quote ( expand m ) ; expand m ;', error:'nesting limit'},
      {source:'macro earlier = quote ( expand later ) ; macro later = quote ( 42 ) ; expand earlier ;',
        error:'unknown macro later'}
    ]) {
      rejects(() -> new TypeChecker().check(entry.source), entry.error);
      rejects(() -> vm.runWithNail(entry.source), entry.error);
      rejects(() -> boot.run(entry.source), entry.error);
    }
    rejects(() -> new TypeChecker().check('macro plus x = quote ( unquote x + 1 ) ; expand plus true ;'), 'cannot unify');
    rejects(() -> new TypeChecker().check('type Option a = None | Some a ; macro incomplete x = quote '
      + '( match unquote x with | Some n -> n ) ; expand incomplete ( Some 1 ) ;'), 'non-exhaustive');
    boot.run('macro transient x = quote ( unquote x ) ; expand transient 1 ;');
    check(boot.names().indexOf('transient') < 0, 'macros must not install runtime bindings');
    rejects(() -> boot.run('expand transient 1 ;'), 'unknown macro transient');
    trace('NailSeed hygienic macro tests passed');
  }
}
