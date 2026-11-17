package numeric;

import nail.NType;

/** Functional, closed type relations for binary arithmetic.
    Every pair of argument types determines at most one result type.
    A relation is an explicit type constraint, not a runtime class. */
typedef BinaryRelationRow = {
  var left:NType;
  var right:NType;
  var result:NType;
}

class NumericRelation {
  static function row(a:NType,b:NType,c:NType):BinaryRelationRow
    return {left:a,right:b,result:c};

  /** The suffix is private checker metadata, not a user-written type name. */
  public static function modernName(name:String):String return switch (name) {
    case 'Div': 'Div45';
    case 'Add' | 'Sub' | 'Mul': name + '46';
    case _: throw 'Type relation: unsupported constraint ' + name;
  };

  public static function surfaceName(name:String):String
    return name == 'Div45' ? 'Div'
      : StringTools.endsWith(name,'46') ? name.substr(0,name.length-2) : name;

  public static function isModern(name:String):Bool
    return name == 'Div45' || name == 'Add46' ||
      name == 'Sub46' || name == 'Mul46';

  static function modernRows(name:String):Array<BinaryRelationRow> {
    var div = surfaceName(name) == 'Div';
    var integer = div ? TRatio : TInt;
    return [
      row(TInt,TInt,integer),
      row(TInt,TRatio,TRatio),
      row(TRatio,TInt,TRatio),
      row(TRatio,TRatio,TRatio),
      row(TFloat,TFloat,TFloat)
    ];
  }

  public static function rows(name:String,
      ?declared:Array<BinaryRelationRow>):Array<BinaryRelationRow> {
    if (name == 'Div')
      return [row(TNumber,TNumber,TNumber),row(TExact,TExact,TExact)];
    if (isModern(name))
      return declared != null && declared.length > 0 ? declared.copy() : modernRows(name);
    throw 'Type relation: unsupported constraint ' + name;
  }

  static function fromName(name:String):NType return switch (name) {
    case 'Int': TInt;
    case 'Ratio': TRatio;
    case 'Float': TFloat;
    case _: throw 'Type relation: unknown numeric type ' + name;
  };

  public static function requireModernRow(left:String,right:String,result:String,
      already:Array<{left:String,right:String,result:String}>,
      relation:String = 'Div'):Void {
    var a=fromName(left), b=fromName(right), c=fromName(result);
    var matched=false;
    for (r in modernRows(modernName(relation)))
      if (Type.enumEq(a,r.left) && Type.enumEq(b,r.right)
          && Type.enumEq(c,r.result)) matched=true;
    if (!matched)
      throw 'Type relation: unsupported '+relation+' row '
        + left + ' ' + right + ' ' + result;
    for (r in already)
      if (r.left == left && r.right == right)
        throw 'Type relation: duplicate '+relation+' input types '
          + left + ' ' + right;
  }

  public static function result(name:String,a:NType,b:NType,
      ?declared:Array<BinaryRelationRow>):NType {
    for (r in rows(name, declared))
      if (Type.enumEq(a,r.left) && Type.enumEq(b,r.right)) return r.result;
    throw 'Type error: no ' + surfaceName(name)
      + ' instance for ' + Type.enumConstructor(a)
      + ' and ' + Type.enumConstructor(b)
      + '; explicit conversion required';
  }

  /** Concrete operations have statically determined results; no Num coercion. */
  public static function operate(op:String,a:NType,b:NType):NType {
    return switch (op) {
      case '/': result('Div45',a,b);
      case '+': result('Add46',a,b);
      case '-': result('Sub46',a,b);
      case '*': result('Mul46',a,b);
      case '<' | '<=' | '>' | '>=':
        if ((Type.enumEq(a,TFloat) && Type.enumEq(b,TFloat)) ||
            ((Type.enumEq(a,TInt) || Type.enumEq(a,TRatio)) &&
             (Type.enumEq(b,TInt) || Type.enumEq(b,TRatio)))) TBoolean
        else throw 'Type error: invalid ' + op + ' operands '
          + Type.enumConstructor(a) + ' and ' + Type.enumConstructor(b)
          + '; explicit conversion required';
      case _: throw 'Type error: unsupported numeric operator ' + op;
    };
  }

  public static function signature(name:String):String {
    rows(name);
    return surfaceName(name) + ' a b c => a -> b -> c';
  }
}
