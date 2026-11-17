package nail;

import nail.Value;

/** JSON-friendly presentation of runtime values, independent of the AST VM. */
class RuntimeValues {
  /** Values converted into JSON-compatible primitive data (functions intentionally excluded). */
  public static function toPlain(value:Value):Dynamic {
    return switch (value) {

      case Number(n): n;
      case IntNumber(n): 'I:' + numeric.FastNumber.encodeExact(n).substr(2);
      case RatioNumber(n): 'R:' + numeric.FastNumber.encodeExact(n).substr(2);
      case ExactNumber(n): numeric.FastNumber.encodeExact(n);
      case Boolean(b): b;
      case Text(s): s;
      case Vector(items): items.map(toPlain);
      case Record(typeName, fields):
        var data:Dynamic = {};
        Reflect.setField(data, "$type", typeName);
        for (name in fields.keys()) Reflect.setField(data, name, toPlain(fields.get(name)));
        data;
      case SyntaxLeaf(kind, value): {tag:kind, value:value};
      case SyntaxNode(kind, children): {tag:kind, children:toPlain(children)};
      case Nil: ([] : Array<Dynamic>);
      case Cons(_, _):
        var items:Array<Dynamic> = [];
        var rest = value;
        var complete = false;
        while (!complete) {
          switch (rest) {
            case Nil: complete = true;
            case Cons(head, tail): items.push(toPlain(head)); rest = tail;
            case _: throw 'Malformed list';
          }
        }
        items;
      case _: throw 'Cannot serialize function value';
    };
  }

  public static function plainResults(values:Array<Value>):Array<Dynamic> {
    return [for (v in values) toPlain(v)];
  }
}
