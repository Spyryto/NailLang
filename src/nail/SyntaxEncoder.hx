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

  /** Encodes deep, left- or right-nested trees without recursive Haxe calls. */
  public static function expr(ast:Expr):Value {
    var pending:Array<{source:Expr, finish:Bool}> = [{source:ast, finish:false}];
    var values:Array<Value> = [];
    while (pending.length > 0) {
      var frame = pending.pop();
      if (frame.finish) {
        switch (frame.source) {
          case Lambda(param, _):
            var body = values.pop();
            values.push(node('Lambda', [leaf('Name', param), body]));
          case Apply(_, _):
            var arg = values.pop();
            var fn = values.pop();
            values.push(node('Apply', [fn, arg]));
          case If(_, _, _):
            var no = values.pop();
            var yes = values.pop();
            var cond = values.pop();
            values.push(node('If', [cond, yes, no]));
          case _: throw 'Bootstrap Syntax encoder: invalid frame';
        }
        continue;
      }
      switch (frame.source) {
        case Literal(Number(n)): values.push(node('Literal', [leaf('Number', Std.string(n))]));
        case Literal(Boolean(b)): values.push(node('Literal', [leaf('Bool', b ? 'true' : 'false')]));
        case Literal(Text(text)): values.push(node('Literal', [leaf('Text', text)]));
        case Literal(Nil): values.push(node('Literal', [leaf('Nil', 'nil')]));
        case Literal(_): throw 'Bootstrap Syntax encoder: unsupported literal';
        case Var(name): values.push(leaf('Var', name));
        case Lambda(_, body):
          pending.push({source:frame.source, finish:true});
          pending.push({source:body, finish:false});
        case Apply(fn, arg):
          pending.push({source:frame.source, finish:true});
          pending.push({source:arg, finish:false});
          pending.push({source:fn, finish:false});
        case If(test, yes, no):
          pending.push({source:frame.source, finish:true});
          pending.push({source:no, finish:false});
          pending.push({source:yes, finish:false});
          pending.push({source:test, finish:false});
      }
    }
    if (values.length != 1) throw 'Bootstrap Syntax encoder: invalid result';
    return values.pop();
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
