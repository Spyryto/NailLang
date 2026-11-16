package nail;

import nail.Ast.Expr;

/** A target-independent value model. Lists are immutable linked cons cells. */
enum Value {
  Number(value:Float);
  Boolean(value:Bool);
  Nil;
  Cons(head:Value, tail:Value);
  Closure(param:String, body:Expr, captured:Env);
  Native(name:String, arity:Int, applied:Array<Value>);
}
