package numeric;

import nail.NType;
import nail.NType.*;
import haxe.ds.StringMap;

/** A finite, functional relation between two input types and a result.
    v0.45 has no implicit exact/Float conversions, and no user-defined
    implementation bodies. The type rows are separate from VM dispatch. */
typedef BinaryRelationRow = {
  var left:NType;
  var right:NType;
  var result:NType;
}

class NumericRelation {
  static function row(a:NType,b:NType,c:NType):BinaryRelationRow
    return {left:a,right:b,result:c};

  public static function rows(name:String,
      ?declared:Array<BinaryRelationRow>):Array<BinaryRelationRow> {
    return switch (name) {
      case 'Div': [row(TNumber,TNumber,TNumber),row(TExact,TExact,TExact)];
      case 'Div45':
        if (declared != null && declared.length > 0) declared.copy() else [
          row(TInt,TInt,TRatio),
          row(TRatio,TRatio,TRatio),
          row(TFloat,TFloat,TFloat),
          row(TInt,TRatio,TRatio),
          row(TRatio,TInt,TRatio)
        ];
      case _: throw 'Type relation: unsupported constraint ' + name;
    };
  }

  static function fromName(name:String):NType return switch (name) {
    case 'Int': TInt;
    case 'Ratio': TRatio;
    case 'Float': TFloat;
    case _: throw 'Type relation: unknown numeric type ' + name;
  };

  public static function requireModernRow(left:String,right:String,result:String,
      already:Array<{left:String,right:String,result:String}>):Void {
    var a=fromName(left), b=fromName(right), c=fromName(result);
    var matched=false;
    for (r in rows('Div45'))
      if (Type.enumEq(a,r.left) && Type.enumEq(b,r.right)
          && Type.enumEq(c,r.result)) matched=true;
    if (!matched)
      throw 'Type relation: unsupported Div row ' + left + ' ' + right + ' ' + result;
    for (r in already)
      if (r.left == left && r.right == right)
        throw 'Type relation: duplicate Div input types ' + left + ' ' + right;
  }

  public static function decodeRows(raw:Array<{left:String,right:String,result:String}>)
      :Array<BinaryRelationRow> {
    if (raw == null) return [];
    if (raw.length > 5) throw 'Type relation: too many Div rows';
    var result:Array<BinaryRelationRow>=[];
    var seen:Array<{left:String,right:String,result:String}>=[];
    for (r in raw) {
      requireModernRow(r.left,r.right,r.result,seen);
      seen.push(r);
      result.push(row(fromName(r.left),fromName(r.right),fromName(r.result)));
    }
    return result;
  }

  public static function result(name:String,a:NType,b:NType,
      ?declared:Array<BinaryRelationRow>):NType {
    for (r in rows(name, declared)) {
      if (Type.enumEq(a,r.left) && Type.enumEq(b,r.right))
        return r.result;
    }
    throw 'Type error: no ' + (name == 'Div45' ? 'Div' : name)
      + ' instance for ' + Type.enumConstructor(a)
      + ' and ' + Type.enumConstructor(b)
      + '; explicit conversion required';
  }

  /** Unconstrained direct operators require concrete known operand types.
      Functions may become overloaded only via the explicit : Div annotation. */
  public static function operate(op:String,a:NType,b:NType):NType {
    if (op == '/') return result('Div45',a,b);
    if (op == '+' || op == '-' || op == '*') {
      if (Type.enumEq(a,TFloat) && Type.enumEq(b,TFloat)) return TFloat;
      if (Type.enumEq(a,TInt) && Type.enumEq(b,TInt)) return TInt;
      if ((Type.enumEq(a,TInt) || Type.enumEq(a,TRatio)) &&
          (Type.enumEq(b,TInt) || Type.enumEq(b,TRatio))) return TRatio;
    } else if (op == '<' || op == '<=' || op == '>' || op == '>=') {
      if ((Type.enumEq(a,TFloat) && Type.enumEq(b,TFloat)) ||
          ((Type.enumEq(a,TInt) || Type.enumEq(a,TRatio)) &&
           (Type.enumEq(b,TInt) || Type.enumEq(b,TRatio)))) return TBoolean;
    }
    throw 'Type error: invalid ' + op + ' operands '
      + Type.enumConstructor(a) + ' and ' + Type.enumConstructor(b)
      + '; explicit conversion required';
  }

  public static function signature(name:String):String {
    rows(name);
    return 'Div a b c => a -> b -> c';
  }
}
