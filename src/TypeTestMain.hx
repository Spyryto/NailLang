import haxe.Json;
import haxe.Resource;
import nail.TypeChecker;

/** Cross-target contract tests for inference (no VM changes). */
class TypeTestMain {
  static function check(ok:Bool, message:String):Void if (!ok) throw message;

  static function main():Void {
    var cases:Dynamic = Json.parse(Resource.getString('type-cases'));
    var stdlib = Resource.getString('stdlib');
    var passed = 0;
    var positive:Array<Dynamic> = cast Reflect.field(cases, 'positive');
    for (item in positive) {
      var checker = new TypeChecker();
      if (Reflect.field(item, 'stdlib') == true) checker.check(stdlib);
      var actual = Json.stringify(checker.check(Reflect.field(item, 'code')));
      var expected = Json.stringify(Reflect.field(item, 'types'));
      check(actual == expected, 'Unexpected inference: ' + Reflect.field(item, 'code')
        + '\nactual=' + actual + '\nexpected=' + expected);
      passed++;
    }
    var negative:Array<Dynamic> = cast Reflect.field(cases, 'negative');
    for (item in negative) {
      var checker = new TypeChecker();
      if (Reflect.field(item, 'stdlib') == true) checker.check(stdlib);
      var error:Null<String> = null;
      try checker.check(Reflect.field(item, 'code')) catch (e:Dynamic) error = Std.string(e);
      var regex = new EReg(Reflect.field(item, 'errorRegex'), '');
      check(error != null && regex.match(error), 'Missing/wrong type error: '
        + Reflect.field(item, 'code') + '\nactual=' + error);
      passed++;
    }
    // Failed batches must not leak definitions into a persistent checker.
    var transactional = new TypeChecker();
    var rejected = false;
    try transactional.check('def okay x = x ; def broken = 1 + true ;') catch (e:Dynamic) rejected = true;
    check(rejected, 'Expected failed type check');
    check(transactional.names().indexOf('okay') < 0, 'Type checker committed rejected batch');
    passed++;
    // Generalization, across separate incremental calls, must keep type variables fresh.
    var incremental = new TypeChecker();
    incremental.check('def id x = x ;');
    check(Json.stringify(incremental.check('id 1 ; id true ;')) == '["Number","Bool"]',
      'Incremental polymorphism failed');
    passed++;
    check(incremental.signature('id') == 'a -> a', 'Wrong generalized id signature');
    passed++;
    incremental.check('def twice x = x * 2 ;');
    check(incremental.signature('twice') == 'Number -> Number', 'Wrong twice signature');
    passed++;
    trace('NailSeed v0.5 types: ' + passed + ' tests passed');
  }
}
