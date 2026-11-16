package nail;

import nail.Ast.Expr;

/** A target-independent value model. Lists are immutable linked cons cells. */
enum Value {
  Number(value:Float);
  Boolean(value:Bool);
  Text(value:String);
  Nil;
  Cons(head:Value, tail:Value);
  /** Typed, first-class source trees; they are values, not additional Expr nodes. */
  SyntaxLeaf(kind:String, text:String);
  SyntaxNode(kind:String, children:Value);
  Closure(param:String, body:Expr, captured:Env);
  /** Closure whose body is already compiled to structured bytecode. */
  ByteClosure(param:String, code:Value, captured:Env);
  Native(name:String, arity:Int, applied:Array<Value>);
}
