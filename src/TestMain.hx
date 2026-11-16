import haxe.Json;
import haxe.Resource;
import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Parser;
import nail.Vm;

/** The same portable JSON contract is checked on --interp, JS and PHP. */
class TestMain {
  static function check(condition:Bool, message:String):Void if (!condition) throw message;

  static function inspect(expr:Expr, kinds:Map<String, Bool>):Void {
    switch (expr) {
      case Literal(_): kinds.set('literal', true);
      case Var(_): kinds.set('var', true);
      case Lambda(_, body): kinds.set('lambda', true); inspect(body, kinds);
      case Apply(fn, arg): kinds.set('apply', true); inspect(fn, kinds); inspect(arg, kinds);
      case If(c, yes, no): kinds.set('if', true); inspect(c, kinds); inspect(yes, kinds); inspect(no, kinds);
    }
  }

  static function main():Void {
    var testData = Resource.getString('cases');
    var stdlib = Resource.getString('stdlib');
    check(testData != null && stdlib != null, 'Missing embedded test resources');
    var cases:Dynamic = Json.parse(testData);
    var passed = 0;
    var positive:Array<Dynamic> = cast Reflect.field(cases, 'positive');
    for (c in positive) {
      var code:String = Reflect.field(c, 'code');
      var vm = new Vm();
      if (Reflect.field(c, 'stdlib') == true) vm.run(stdlib);
      var actual = Json.stringify(Vm.plainResults(vm.run(code)));
      var expected = Json.stringify(Reflect.field(c, 'expected'));
      check(actual == expected, 'Mismatch: ' + code + '\nactual=' + actual + '\nexpected=' + expected);
      passed++;
    }
    var negative:Array<Dynamic> = cast Reflect.field(cases, 'negative');
    for (c in negative) {
      var code:String = Reflect.field(c, 'code');
      var pattern = new EReg(Reflect.field(c, 'errorRegex'), '');
      var error:Null<String> = null;
      try {
        new Vm(128).run(code);
      } catch (e:Dynamic) {
        error = Std.string(e);
      }
      check(error != null && pattern.match(error), 'Wrong/missing error: ' + code + '\ngot=' + error);
      passed++;
    }
    var kinds:Map<String, Bool> = new Map();
    for (form in new Parser('def twice x = if true then x * 2 else 0 ; let x = 3 in x ; match [ 1 ] with | [] -> 0 | h :: t -> h ;').parse()) {
      switch (form) {
        case Define(_, body) | Evaluate(body): inspect(body, kinds);
      }
    }
    check([for (k in kinds.keys()) k].length == 5, 'Expected five expression kinds');
    passed++;
    trace('NailSeed v0.8: ' + passed + ' tests passed');
  }
}
