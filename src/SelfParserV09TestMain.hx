import haxe.Json;
import haxe.Resource;
import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Parser;
import nail.Value;
import nail.Vm;
import nail.SyntaxBridge;
import nail.TypeChecker;

/** v0.9 cross-parser comparison, error checks and actual execution of self-parsed trees. */
class SelfParserV09TestMain {
  static function list(values:Array<Value>):Value {
    var result:Value = Nil;
    var i = values.length;
    while (i > 0) { i--; result = Cons(values[i], result); }
    return result;
  }
  static function leaf(tag:String, text:String):Value return SyntaxLeaf(tag, text);
  static function node(tag:String, children:Array<Value>):Value return SyntaxNode(tag, list(children));

  static function expression(expr:Expr):Value {
    return switch (expr) {
      case Literal(Number(n)): node('Literal', [leaf('Number', Std.string(n))]);
      case Literal(Boolean(b)): node('Literal', [leaf('Bool', b ? 'true' : 'false')]);
      case Literal(Nil): node('Literal', [leaf('Nil', 'nil')]);
      case Literal(Text(s)): node('Literal', [leaf('Text', s)]);
      case Literal(_): throw 'Unexpected literal';
      case Var(name): leaf('Var', name);
      case Lambda(param, body): node('Lambda', [leaf('Name', param), expression(body)]);
      case Apply(fn, arg): node('Apply', [expression(fn), expression(arg)]);
      case If(test, yes, no): node('If', [expression(test), expression(yes), expression(no)]);
    };
  }
  static function canonical(source:String):Value {
    var forms:Array<Value> = [];
    for (form in new Parser(source).parse()) {
      switch (form) {
        case Define(name, body): forms.push(node('Define', [leaf('Name', name), expression(body)]));
        case Evaluate(body): forms.push(node('Evaluate', [expression(body)]));
        case RecordType(_, _): throw 'No record declarations in legacy parser tests';
      }
    }
    return node('Program', forms);
  }

  static function normalizeTree(value:Value):Value {
    return switch (value) {
      case SyntaxLeaf(tag, text):
        // The bootstrap parser allocates fresh hidden indices; the source-level
        // parser uses private lexical names, which are alpha-equivalent.
        if ((tag == 'Var' || tag == 'Name') && StringTools.startsWith(text, '#nail_')) {
          var match = ~/^#nail_(list|wild_head|wild_tail)(?:_\d+)?$/;
          if (match.match(text)) leaf(tag, '#nail_' + match.matched(1)) else value;
        } else value;
      case SyntaxNode(tag, children):
        var output:Array<Value> = [];
        var rest = children;
        var done = false;
        while (!done) {
          switch (rest) {
            case Nil: done = true;
            case Cons(head, tail): output.push(normalizeTree(head)); rest = tail;
            case _: throw 'Malformed Syntax list';
          }
        }
        node(tag, output);
      case _: value;
    };
  }
  static function checkTree(vm:Vm, source:String):Void {
    var parsed = vm.parseWithNail(source);
    var expected = normalizeTree(canonical(source));
    var actual = normalizeTree(parsed);
    var a = Json.stringify(Vm.toPlain(actual));
    var e = Json.stringify(Vm.toPlain(expected));
    if (a != e) throw 'Self-parser AST mismatch for ' + source + '\nExpected: ' + e + '\nActual: ' + a;
    // Check that SyntaxBridge can reconstruct the core AST without reparsing.
    var converted = SyntaxBridge.forms(parsed);
    if (converted.length != new Parser(source).parse().length) throw 'Wrong program length';
  }

  static function checkExecution(source:String, expected:String):Void {
    var vm = new Vm(10000000);
    vm.loadStdlib();
    var actual = Json.stringify(Vm.plainResults(vm.runWithNail(source)));
    if (actual != expected) throw 'Self-parser execution mismatch: ' + source + '\nExpected ' + expected + '\nActual ' + actual;
  }
  static function checkError(vm:Vm, source:String):Void {
    var result = vm.parseWithNail(source);
    var tag = switch (result) {
      case SyntaxLeaf(tag, _): tag;
      case SyntaxNode(tag, _): tag;
      case _: throw 'Not a syntax tree';
    };
    if (tag != 'Error') throw 'Expected self-parser Error for ' + source + ', got ' + tag;
    try {
      SyntaxBridge.forms(result);
      throw 'SyntaxBridge accepted a malformed source';
    } catch (e:Dynamic) {
      if (Std.string(e) == 'SyntaxBridge accepted a malformed source') throw e;
    }
  }

  static function main():Void {
    var vm = new Vm(10000000);
    vm.loadStdlib();
    var good = [
      '" hello there " ;',
      '" " ;',
      'def label x = " hello world " ;',
      '[ " a b " , " c " ] ;',
      'if true then " yes " else " no " ;',
      'let s = " hi " in s ;',
      'match [] with | [] -> 1 | x :: xs -> x ;',
      'match [ 1 , 2 ] with | [] -> 0 | h :: t -> h ;',
      'match [ 1 , 2 ] with | x :: rest -> rest | [] -> [] ;',
      'match [ 1 ] with | [] -> 0 | _ :: t -> 9 ;',
      'match [ 1 ] with | h :: _ -> h | [] -> 0 ;',
      'def sum xs = match xs with | [] -> 0 | x :: rest -> x + sum rest ;',
      'let f = fun xs -> match xs with | [] -> 0 | h :: t -> h in f [ 7 ] ;',
      'match [ [ 1 ] ] with | [] -> [] | x :: xs -> match x with | [] -> [] | h :: t -> t ;',
      'def text x = if x then " yes " else " no " ;',
      'def f x = match x with | [] -> 0 | a :: tail -> a * 2 ; f [ 3 ] ;',
      '1 + 2 ; # a comment\n3 + 4 ;',
      '" hash # and spaces " ; # comment'
    ];
    for (source in good) checkTree(vm, source);
    var errors = [
      '" unterminated ;',
      '" unknown\\q " ;',
      'match [] with | [] -> 1 ;',
      'match [] with | [] -> 1 | [] -> 2 ;',
      'match [] with | h :: t -> h | x :: xs -> 0 ;',
      'match [ 1 ] with | h :: h -> 1 | [] -> 0 ;',
      'match [] with | [] 1 | x :: xs -> 0 ;',
      'match [] with | [] -> 1 | 1 -> 0 ;',
      'match [] with | [] -> 1 | h :: -> 0 ;',
      '" noSpace "x ;'
    ];
    for (source in errors) checkError(vm, source);
    checkExecution('def sum xs = match xs with | [] -> 0 | h :: t -> h + sum t ; sum [ 1 , 2 , 3 ] ;', '[6]');
    checkExecution('match [] with | [] -> 42 | h :: t -> 0 ;', '[42]');
    checkExecution('match [ 4 , 5 ] with | [] -> 0 | h :: t -> h ;', '[4]');
    checkExecution('" hello world " ;', '["hello world"]');
    checkExecution('def twice x = x * 2 ; twice 4 ;', '[8]');
    checkExecution('let x = 4 in x + 1 ;', '[5]');
    checkExecution('def pick xs = match xs with | [] -> false | x :: rest -> x ; pick [ true ] ;', '[true]');
    // The existing Hindley-Milner checker can check the reconstructed forms.
    var checker = new TypeChecker();
    checker.check(Resource.getString('stdlib'));
    var syntax = vm.parseWithNail('def headOrZero xs = match xs with | [] -> 0 | h :: rest -> h ; headOrZero [ 5 ] ;');
    var inferred = checker.checkSyntax(syntax);
    if (Json.stringify(inferred) != '["Number"]') throw 'CheckSyntax failed ' + Json.stringify(inferred);
    trace('NailSeed v0.9 self-parser: ' + (good.length + errors.length + 7 + 1) + ' tests passed');
  }
}
