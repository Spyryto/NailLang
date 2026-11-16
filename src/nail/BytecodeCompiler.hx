package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;

/** Independent Haxe reference compiler for the five-variant core AST.
    The instruction representation is plain immutable Syntax data so that
    exactly the same bytecode can be created by Nail source code. */
class BytecodeCompiler {
  static function list(items:Array<Value>):Value {
    var result:Value = Nil;
    var index = items.length;
    while (index > 0) {
      index--;
      result = Cons(items[index], result);
    }
    return result;
  }

  static function node(tag:String, children:Array<Value>):Value return SyntaxNode(tag, list(children));
  static function leaf(tag:String, text:String):Value return SyntaxLeaf(tag, text);
  static function code(items:Array<Value>):Value return node('Code', items);
  static function instruction0(tag:String):Value return node(tag, []);
  static function instruction1(tag:String, a:Value):Value return node(tag, [a]);
  static function instruction2(tag:String, a:Value, b:Value):Value return node(tag, [a, b]);

  static function literal(v:Value):Value {
    var primitive:Value = switch (v) {
      case Number(n): leaf('Number', Std.string(n));
      case Boolean(b): leaf('Bool', b ? 'true' : 'false');
      case Text(s): leaf('Text', s);
      case Nil: leaf('Nil', 'nil');
      case _: throw 'Cannot compile non-literal value';
    };
    return node('Literal', [primitive]);
  }

  /** Tail positions use a terminal TAIL_CALL rather than CALL/RETURN.
      Non-tail branches remain ordinary expression blocks. */
  static function emit(expr:Expr, tail:Bool):Array<Value> {
    var instructions = switch (expr) {
      case Literal(value): [instruction1('CONST', literal(value))];
      case Var(name): [instruction1('LOAD', leaf('Var', name))];
      case Lambda(param, body): [instruction2('CLOSURE', leaf('Name', param), code(emit(body, true)))];
      case Apply(fn, arg): emit(fn, false).concat(emit(arg, false)).concat([instruction0(tail ? 'TAIL_CALL' : 'CALL')]);
      case If(condition, yes, no):
        emit(condition, false).concat([instruction2('BRANCH', code(emit(yes, tail)), code(emit(no, tail)))]);
    };
    // A tail BRANCH delegates termination to the chosen branch. A tail
    // application terminates via TAIL_CALL. Values terminate via RETURN.
    return if (tail) switch (expr) {
      case Apply(_, _) | If(_, _, _): instructions;
      case _: instructions.concat([instruction0('RETURN')]);
    } else instructions;
  }

  public static function compile(forms:Array<Form>):Value {
    var result:Array<Value> = [];
    for (form in forms) {
      result.push(switch (form) {
        case Define(name, body): instruction2('DEFINE', leaf('Name', name), code(emit(body, true)));
        case Evaluate(body): instruction1('EVAL', code(emit(body, true)));
      });
    }
    return node('Bytecode', result);
  }

  public static function compileSource(source:String):Value return compile(new Parser(source).parse());
  public static function compileSyntax(tree:Value):Value return compile(SyntaxBridge.forms(tree));
}
