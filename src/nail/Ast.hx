package nail;

/** The complete expression core: exactly five constructors. */
enum Expr {
  Literal(value:Value);
  Var(name:String);
  Lambda(param:String, body:Expr);
  Apply(fn:Expr, argument:Expr);
  If(condition:Expr, whenTrue:Expr, whenFalse:Expr);
}

/** A named immutable record field. The v0.17 grammar uses simple nominal
    field types; recursive and generic user-defined types are deferred. */
typedef RecordField = { name:String, typeName:String };
typedef SumConstructor = { name:String, fieldTypes:Array<String> };

/** Definitions are program forms, not additional expression constructors. */
enum Form {
  Define(name:String, body:Expr);
  Evaluate(body:Expr);
  RecordType(name:String, params:Array<String>, fields:Array<RecordField>);
  SumType(name:String, params:Array<String>, constructors:Array<SumConstructor>);
}
