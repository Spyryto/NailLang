package numeric;

import nail.NType;

/** v0.44 first closed numerical relation, with no source-defined instances.
    The stable relation syntax is intended to admit Int/Ratio/Float when the
    full numeric redesign lands. Existing types here are Number and Exact.
    No implicit numeric-constrained generalization is performed. */
typedef BinaryRelationRow = {
  var left:NType;
  var right:NType;
  var result:NType;
}

class NumericRelation {
  public static function rows(name:String):Array<BinaryRelationRow> {
    return switch (name) {
      case 'Div': [
        {left:TNumber, right:TNumber, result:TNumber},
        {left:TExact, right:TExact, result:TExact}
      ];
      case _: throw 'Type relation: unsupported constraint ' + name;
    };
  }

  public static function result(name:String,a:NType,b:NType):NType {
    for (row in rows(name)) {
      if (Type.enumEq(a,row.left) && Type.enumEq(b,row.right))
        return row.result;
    }
    throw 'Type error: no ' + name + ' instance for '
      + Type.enumConstructor(a) + ' and ' + Type.enumConstructor(b)
      + '; explicit conversion required';
  }

  public static function signature(name:String):String {
    rows(name);
    return name + ' a b c => a -> b -> c';
  }
}
