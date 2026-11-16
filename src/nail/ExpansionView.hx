package nail;

import haxe.Json;
import nail.Ast.Expr;
import nail.Ast.Form;

/** Display the expanded core with explicit names for generated and global bindings. */
class ExpansionView {
  public static function render(forms:Array<Form>):String {
    return forms.map(form -> switch (form) {
      case Define(name, body): 'def ' + name + ' = ' + expr(body) + ' ;';
      case Evaluate(body): expr(body) + ' ;';
      case RecordType(name, params, fields):
        'type ' + [name].concat(params).join(' ') + ' { ' + fields.map(f -> f.name + ' ' + f.typeName).join(' ') + ' } ;';
      case SumType(name, params, constructors):
        'type ' + [name].concat(params).join(' ') + ' = '
          + constructors.map(c -> [c.name].concat(c.fieldTypes).join(' ')).join(' | ') + ' ;';
    }).join('\n');
  }

  static function name(label:String):String {
    if (StringTools.startsWith(label, MacroExpander.GLOBAL))
      return 'global[' + MacroExpander.globalName(label) + ']';
    if (StringTools.startsWith(label, '#macro_local_')) {
      var generated = label.substr('#macro_local_'.length);
      var boundary = generated.indexOf('_');
      if (boundary >= 0) return generated.substr(boundary + 1) + '@' + generated.substr(0, boundary);
    }
    return label;
  }

  // Explicit work stack keeps the view available for deep compiler-generated trees.
  static function expr(root:Expr):String {
    var output = new StringBuf();
    var work:Array<ViewToken> = [Expression(root)];
    while (work.length > 0) switch (work.pop()) {
      case Text(fragment): output.add(fragment);
      case Expression(value):
        switch (value) {
          case Var(label): output.add(name(label));
          case Literal(Number(n)): output.add(Std.string(n));
          case Literal(Boolean(b)): output.add(Std.string(b));
          case Literal(Text(s)): output.add(Json.stringify(s));
          case Literal(Nil): output.add('[]');
          case Literal(_): throw 'Unexpected literal in expanded expression';
          case Lambda(param, body):
            work.push(Text(' )'));
            work.push(Expression(body));
            work.push(Text('( fun ' + name(param) + ' -> '));
          case Apply(fn, argument):
            work.push(Text(' )'));
            work.push(Expression(argument));
            work.push(Text(' '));
            work.push(Expression(fn));
            work.push(Text('( '));
          case If(condition, yes, no):
            work.push(Text(' )'));
            work.push(Expression(no));
            work.push(Text(' else '));
            work.push(Expression(yes));
            work.push(Text(' then '));
            work.push(Expression(condition));
            work.push(Text('( if '));
        }
    }
    return output.toString();
  }
}

private enum ViewToken {
  Text(fragment:String);
  Expression(value:Expr);
}
