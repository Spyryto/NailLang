import haxe.Json;
import haxe.Resource;
import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Parser;
import nail.Value;
import nail.Vm;

/** Compare source-level Pratt parser (written in Nail) to the bootstrap Haxe parser. */
class SelfParserTestMain {
  static function list(values:Array<Value>):Value {
    var result:Value = Nil;
    var i = values.length;
    while (i > 0) { i--; result = Cons(values[i], result); }
    return result;
  }

  static function leaf(tag:String, text:String):Value return SyntaxLeaf(tag, text);
  static function node(tag:String, values:Array<Value>):Value return SyntaxNode(tag, list(values));

  static function expression(expr:Expr):Value {
    return switch (expr) {
      case Literal(Number(n)): node('Literal', [leaf('Number', Std.string(n))]);
      case Literal(Boolean(b)): node('Literal', [leaf('Bool', b ? 'true' : 'false')]);
      case Literal(Nil): node('Literal', [leaf('Nil', 'nil')]);
      case Literal(Text(t)): node('Literal', [leaf('Text', t)]);
      case Literal(_): throw 'Unexpected literal';
      case Var(name): leaf('Var', name);
      case Lambda(name, body): node('Lambda', [leaf('Name', name), expression(body)]);
      case Apply(fn, arg): node('Apply', [expression(fn), expression(arg)]);
      case If(condition, yes, no): node('If', [expression(condition), expression(yes), expression(no)]);
    };
  }

  static function canonical(source:String):Value {
    var forms:Array<Value> = [];
    for (form in new Parser(source).parse()) {
      switch (form) {
        case Define(name, body): forms.push(node('Define', [leaf('Name', name), expression(body)]));
        case Evaluate(body): forms.push(node('Evaluate', [expression(body)]));
      }
    }
    return node('Program', forms);
  }

  static function assertTree(vm:Vm, source:String):Void {
    if (source.indexOf('"') >= 0 || source.indexOf('#') >= 0)
      throw 'Test cases cannot contain quote delimiters or comments';
    var actual = Json.stringify(vm.runPlain('parseSource " ' + source + ' " ;')[0]);
    var expected = Json.stringify(Vm.toPlain(canonical(source)));
    if (actual != expected) throw 'Parser tree mismatch for: ' + source + '\nexpected=' + expected + '\nactual=' + actual;
  }

  static function assertError(vm:Vm, source:String):Void {
    var results = vm.runPlain('parseSource " ' + source + ' " ;');
    var tree:Dynamic = results[0];
    if (Reflect.field(tree, 'tag') != 'Error') throw 'Expected parser Error for: ' + source + ' got: ' + Json.stringify(tree);
  }

  static function main():Void {
    var vm = new Vm(3000000);
    vm.loadStdlib();
    var good = [
      '1 ;',
      'true ; false ; [] ;',
      '[ ] ; [ 1 , 2 , 3 ] ;',
      'x ;',
      '-3 ; 0.125 ;',
      '1 + 2 * 3 ;',
      '( 1 + 2 ) * 3 ;',
      '10 / 2 - 3 ;',
      'f x y ;',
      'f ( g x ) ;',
      'f ( 1 + 2 ) ;',
      'fun x -> x ;',
      'fun x y -> x + y ;',
      'if true then 1 else 2 ;',
      'if 1 < 2 then 4 else 5 ;',
      'let x = 1 in x + 2 ;',
      'let f = fun x -> x in f true ;',
      'def twice x = x * 2 ; twice 3 ;',
      'def add a b = a + b ;',
      'def x = 1 ;',
      'def inc x = if x < 0 then 0 else x + 1 ;',
      'def f xs = [ 1 , 2 ] ;',
      '[ f 1 , g ( x + y ) , 3 ] ;',
      '1 == 1 ; 1 != 2 ; 3 <= 4 ;',
      'def factorial n = if n < 2 then 1 else n * factorial ( n - 1 ) ;'
    ];
    for (source in good) assertTree(vm, source);
    var bad = [
      'def twice x x = x ;',
      'def x = 1',
      'def = 1 ;',
      '1 + ;',
      '[ 1 2 ;',
      '[ 1 , ;',
      '( 1 + 2 ;',
      'if true then 1 ;',
      'fun -> 1 ;',
      'let 1 = 2 in 3 ;',
      '1 ) ;',
      '+ 1 ;'
    ];
    for (source in bad) assertError(vm, source);
    trace('NailSeed v0.8 self-hosted parser: ' + (good.length + bad.length) + ' cross-parser tests passed');
  }
}
