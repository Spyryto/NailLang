package nail;

import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Ast.SumConstructor;
import nail.Value;

class SumLowering {
  static function call(fn:Expr, arg:Expr):Expr return Apply(fn, arg);
  static function text(s:String):Expr return Literal(Text(s));
  static function list(items:Array<Expr>):Expr {
    var out:Expr = Literal(Nil);
    var i = items.length;
    while (i > 0) { i--; out = call(call(Var('#cons'), items[i]), out); }
    return out;
  }
  static function field(value:Expr, key:String):Expr return call(call(Var('#recordGet'), value), text(key));

  public static function definitions(typeName:String, constructors:Array<SumConstructor>):Array<Form> {
    var forms:Array<Form> = [];
    for (ctor in constructors) {
      var fields:Array<Expr> = [text('#tag')];
      var values:Array<Expr> = [text(ctor.name)];
      for (i in 0...ctor.fieldTypes.length) {
        fields.push(text('#' + i));
        values.push(Var('#arg' + i));
      }
      var construct:Expr = call(call(call(Var('#recordMake'), text(typeName)), list(fields)), list(values));
      var i = ctor.fieldTypes.length;
      while (i > 0) { i--; construct = Lambda('#arg' + i, construct); }
      forms.push(Define(ctor.name, construct));
      var receiver:Expr = Var('#sum');
      var isExpr:Expr = Lambda('#sum', call(call(Var('=='), field(receiver, '#tag')), text(ctor.name)));
      forms.push(Define(ctor.name + '?', isExpr));
      for (j in 0...ctor.fieldTypes.length) {
        var getExpr:Expr = Lambda('#sum', If(
          call(Var(ctor.name + '?'), receiver), field(receiver, '#' + j),
          call(Var('#sumFail'), receiver)));
        forms.push(Define(ctor.name + '.' + j, getExpr));
      }
    }
    return forms;
  }

  public static function lowerMatch(value:Expr, branches:Array<{name:String, params:Array<String>, body:Expr}>):Expr {
    if (branches.length == 0) throw 'Match needs at least one variant branch';
    var target:Expr = Var('#nail_sum_subject_0');
    var result:Expr = call(Var('#sumFail'), target);
    var i = branches.length;
    while (i > 0) {
      i--;
      var branch = branches[i];
      var body = branch.body;
      var j = branch.params.length;
      while (j > 0) {
        j--;
        var param = branch.params[j] == '_' ? '#nail_wild_sum_' + j : branch.params[j];
        body = call(Lambda(param, body), call(Var(branch.name + '.' + j), target));
      }
      result = If(call(Var(branch.name + '?'), target), body, result);
    }
    return call(Lambda('#nail_sum_subject_0', result), value);
  }
}
