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
  /** Iterative post-order compilation. Structured blocks retain the original ISA.
      Intermediate arrays are deliberately local to each expression node. */
  static function emit(expr:Expr, tail:Bool):Array<Value> {
    var pending:Array<{source:Expr, tail:Bool, finish:Bool}> = [
      {source:expr, tail:tail, finish:false}
    ];
    var emitted:Array<Array<Value>> = [];
    while (pending.length > 0) {
      var frame = pending.pop();
      var ins:Array<Value>;
      if (frame.finish) {
        ins = switch (frame.source) {
          case Lambda(param, _):
            var body = emitted.pop();
            [instruction2('CLOSURE', leaf('Name', param), code(body))];
          case Apply(_, _):
            var arg = emitted.pop();
            var fn = emitted.pop();
            fn.concat(arg).concat([instruction0(frame.tail ? 'TAIL_CALL' : 'CALL')]);
          case If(_, _, _):
            var no = emitted.pop();
            var yes = emitted.pop();
            var condition = emitted.pop();
            condition.concat([instruction2('BRANCH', code(yes), code(no))]);
          case _: throw 'Invalid compiler frame';
        };
      } else {
        switch (frame.source) {
          case Literal(value): ins = [instruction1('CONST', literal(value))];
          case Var(name): ins = [instruction1('LOAD', leaf('Var', name))];
          case Lambda(_, body):
            pending.push({source:frame.source, tail:frame.tail, finish:true});
            pending.push({source:body, tail:true, finish:false});
            continue;
          case Apply(fn, arg):
            pending.push({source:frame.source, tail:frame.tail, finish:true});
            pending.push({source:arg, tail:false, finish:false});
            pending.push({source:fn, tail:false, finish:false});
            continue;
          case If(condition, yes, no):
            pending.push({source:frame.source, tail:frame.tail, finish:true});
            pending.push({source:no, tail:frame.tail, finish:false});
            pending.push({source:yes, tail:frame.tail, finish:false});
            pending.push({source:condition, tail:false, finish:false});
            continue;
        }
      }
      if (frame.tail) switch (frame.source) {
        case Apply(_, _) | If(_, _, _): // Branches and tail calls are terminal.
        case _: ins.push(instruction0('RETURN'));
      }
      emitted.push(ins);
    }
    if (emitted.length != 1) throw 'Invalid compiler result';
    return emitted.pop();
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
