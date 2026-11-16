import haxe.Json;
import haxe.Resource;
import nail.BootstrapImage;
import nail.BootRuntime;
import nail.Value;

/** All tests in this class use only the embedded bytecode image. Compiled with
    -D nail_seed_only so Vm.run() explicitly refuses the host source parser. */
class BootTestMain {
  static var checks = 0;

  static function check(source:String, expected:String):Void {
    var boot = new BootRuntime(30000000);
    var actual = Json.stringify(boot.runPlain(source));
    if (actual != expected) throw 'Boot result mismatch: ' + source + '\nexpected ' + expected + '\ngot ' + actual;
    checks++;
  }

  static function rejects(source:String):Void {
    var boot = new BootRuntime(30000000);
    try {
      boot.runPlain(source);
      throw 'Bad Nail code accepted: ' + source;
    } catch (error:Dynamic) {
      if (Std.string(error).indexOf('Bad Nail code accepted: ') >= 0) throw error;
    }
    checks++;
  }

  static function rejectsImage(text:String):Void {
    try {
      BootstrapImage.decode(text);
      throw 'Malformed image accepted';
    } catch (error:Dynamic) {
      if (Std.string(error) == 'Malformed image accepted') throw error;
    }
    checks++;
  }

  static function main():Void {
    var image = Resource.getString('bootstrap_image');
    if (image == null) throw 'Missing image';
    var program = BootstrapImage.decode(image);
    // JSON object field order is target-dependent, but the postfix record
    // array must roundtrip exactly, preserving the full canonical tape.
    var originalTape:Dynamic = Reflect.field(Json.parse(image), 'records');
    var decodedTape:Dynamic = Reflect.field(Json.parse(BootstrapImage.encode(program)), 'records');
    if (Json.stringify(originalTape) != Json.stringify(decodedTape))
      throw 'Noncanonical bootstrap record tape';
    checks++;

    var boot = new BootRuntime(30000000);
    for (name in ['parseSource', 'compileSource', 'compileSyntax', 'map', 'fold'])
      if (boot.names().indexOf(name) < 0) throw 'Missing compiled bootstrap function: ' + name;
    checks++;

    check(' 2 + 3 ; ', '[5]');
    check('def triple x = x * 3 ; triple 14 ;', '[42]');
    check('def add a b = a + b ; def add10 = add 10 ; add10 5 ;', '[15]');
    check('map ( fun x -> x + 3 ) [ 1 , 2 , 3 ] ;', '[[4,5,6]]');
    check('fold ( fun acc x -> acc + x ) 0 [ 1 , 2 , 3 , 4 ] ;', '[10]');
    check('match [ 8 , 4 ] with | [] -> 0 | h :: t -> h ;', '[8]');
    check('let id = fun x -> x in id true ;', '[true]');
    check('if false then 1 / 0 else 13 ;', '[13]');
    check('syntaxTag ( parseSource " 1 + 2 ; " ) ;', '["Program"]');
    check('def walk n total = if n == 0 then total else walk ( n - 1 ) ( total + 1 ) ; walk 6000 0 ;', '[6000]');
    rejects('1 + ;');
    rejects('def x = ;');
    rejects('if true then ;');

    var compiled = boot.compile(' 7 * 6 ; ');
    if (Json.stringify(boot.runBytecode(compiled).map(nail.Vm.toPlain)) != '[42]')
      throw 'Compiling and running Syntax bytecode failed';
    checks++;

    rejectsImage('{}');
    rejectsImage('{"format":"nailseed.postfix-image.v1","records":[["N","Bytecode",1]]}');
    rejectsImage('{"format":"nailseed.postfix-image.v1","records":[["L","Text","x"]]}');

    // The serializer itself also handles deeply nested structures iteratively.
    var nested:Value = SyntaxLeaf('Var', 'x');
    for (_ in 0...3500) nested = SyntaxNode('Chain', Cons(nested, Nil));
    var large:Value = SyntaxNode('Bytecode', Cons(nested, Nil));
    var recovered = BootstrapImage.decode(BootstrapImage.encode(large));
    var count = 0;
    switch (recovered) {
      case SyntaxNode('Bytecode', Cons(first, Nil)):
        var cursor = first;
        var done = false;
        while (!done) {
          switch (cursor) {
            case SyntaxNode('Chain', Cons(inner, Nil)):
              count++;
              cursor = inner;
            case SyntaxLeaf('Var', 'x'):
              done = true;
            case _: throw 'Malformed deeply nested bootstrap image';
          }
        }
      case _: throw 'Malformed bootstrap image root';
    }
    if (count != 3500) throw 'Wrong nested bootstrap depth';
    checks++;

    trace('NailSeed v0.14: ' + checks + ' source-free bootstrap tests passed');
  }
}
