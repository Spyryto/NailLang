package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Ast.RecordField;
import nail.Value;

/** Compiles record declarations into ordinary lambdas and primitive calls.
    Five expression AST constructors, no additional bytecode instruction. */
class RecordLowering {
  static function call(fn:Expr, arg:Expr):Expr return Apply(fn, arg);
  static function list(items:Array<Expr>):Expr {
    var out:Expr = Literal(Nil);
    var i = items.length;
    while (i > 0) {
      i--;
      out = call(call(Var('#cons'), items[i]), out);
    }
    return out;
  }

  public static function definitions(name:String, fields:Array<RecordField>):Array<Form> {
    if (fields.length == 0) throw 'Record requires at least one field';
    var names:Array<Expr> = [];
    var values:Array<Expr> = [];
    for (field in fields) {
      names.push(Literal(Text(field.name)));
      values.push(Var(field.name));
    }
    var constructor:Expr = call(
      call(call(Var('#recordMake'), Literal(Text(name))), list(names)), list(values));
    var i = fields.length;
    while (i > 0) { i--; constructor = Lambda(fields[i].name, constructor); }
    var definitions:Array<Form> = [Define(name, constructor)];
    for (field in fields) {
      var accessor:Expr = Lambda('#rec', call(call(Var('#recordGet'),
        Var('#rec')), Literal(Text(field.name))));
      definitions.push(Define(name + '.' + field.name, accessor));
    }
    return definitions;
  }
}
