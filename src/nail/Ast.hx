package nail;

/** The complete expression core: exactly five constructors. */
enum Expr {
  Literal(value:Value);
  Var(name:String);
  Lambda(param:String, body:Expr);
  Apply(fn:Expr, argument:Expr);
  If(condition:Expr, whenTrue:Expr, whenFalse:Expr);
}

/** Definitions are program forms, not additional expression constructors. */
enum Form {
  Define(name:String, body:Expr);
  Evaluate(body:Expr);
}
