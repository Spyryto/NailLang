package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;

/** Host bootstrap encoder: converts the already-parsed five-node AST to the
    first-class Syntax representation accepted by the Nail-written compiler.
    It does not generate bytecode and is not used by normal self-parsed source. */
class SyntaxEncoder {
  static function list(values:Array<Value>):Value {
    var result:Value = Nil;
    var i = values.length;
    while (i > 0) { i--; result = Cons(values[i], result); }
    return result;
  }
  static function leaf(tag:String, text:String):Value return SyntaxLeaf(tag, text);
  static function node(tag:String, children:Array<Value>):Value return SyntaxNode(tag, list(children));

  public static function expr(ast:Expr):Value {
    return switch (ast) {
      case Literal(Number(n)): node('Literal', [leaf('Number', Std.string(n))]);
      case Literal(Boolean(b)): node('Literal', [leaf('Bool', b ? 'true' : 'false')]);
      case Literal(Text(s)): node('Literal', [leaf('Text', s)]);
      case Literal(Nil): node('Literal', [leaf('Nil', 'nil')]);
      case Literal(_): throw 'Bootstrap Syntax encoder: unsupported literal';
      case Var(name): leaf('Var', name);
      case Lambda(param, body): node('Lambda', [leaf('Name', param), expr(body)]);
      case Apply(fn, arg): node('Apply', [expr(fn), expr(arg)]);
      case If(test, yes, no): node('If', [expr(test), expr(yes), expr(no)]);
    };
  }

  public static function program(forms:Array<Form>):Value {
    var encoded:Array<Value> = [];
    for (form in forms) {
      encoded.push(switch (form) {
        case Define(name, body): node('Define', [leaf('Name', name), expr(body)]);
        case Evaluate(body): node('Evaluate', [expr(body)]);
      });
    }
    return node('Program', encoded);
  }
}
