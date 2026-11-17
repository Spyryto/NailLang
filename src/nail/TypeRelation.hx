package nail;

import haxe.ds.StringMap;
import nail.NType;

/** Finite, named, first-order type relation, independent of numeric
    operators and runtime dispatch. The final column is always the result.
    Input tuples functionally determine the final type. */
typedef RelationContract = {
  var name:String;
  var rows:Array<Array<NType>>;
}

class TypeRelation {
  public static inline var MAX_ARITY = 16;
  public static inline var MAX_ROWS = 128;

  public static function typeName(ty:NType):String return switch (ty) {
    case TInt: 'Int';
    case TRatio: 'Ratio';
    case TFloat: 'Float';
    case TBoolean: 'Bool';
    case TText: 'Text';
    case TSyntax: 'Syntax';
    case TRecord(name): name;
    case _: throw 'Type relation: only concrete atomic types are supported';
  };

  public static function parseType(token:String):NType return switch (token) {
    case 'Int': TInt;
    case 'Ratio': TRatio;
    case 'Float': TFloat;
    case 'Bool': TBoolean;
    case 'Text' | 'String': TText;
    case 'Syntax': TSyntax;
    case name if (~/^[A-Z][A-Za-z0-9_]*$/.match(name)): TRecord(name);
    case _: throw 'Type relation: unknown type ' + token;
  };

  public static function parseRow(names:Array<String>):Array<NType> {
    if (names.length < 2 || names.length > MAX_ARITY + 1)
      throw 'Type relation: expected 1 to 16 parameter types and one result type';
    return [for (name in names) parseType(name)];
  }

  public static function validate(raw:RelationContract):RelationContract {
    if (raw == null || raw.rows == null ||
        !~/^[A-Z][A-Za-z0-9_]*$/.match(raw.name) ||
        raw.rows.length == 0 || raw.rows.length > MAX_ROWS)
      throw 'Type relation: invalid relation table';
    var arity=-1;
    var seen = new StringMap<Bool>();
    var result:Array<Array<NType>>=[];
    for (row in raw.rows) {
      if (row == null || row.length < 2 || row.length > MAX_ARITY + 1)
        throw 'Type relation: invalid signature in ' + raw.name;
      if (arity != -1 && arity != row.length - 1)
        throw 'Type relation: inconsistent arity for ' + raw.name;
      arity = row.length - 1;
      var tokens=[for (item in row) typeName(item)];
      var key=tokens.slice(0,arity).join('|');
      if (seen.exists(key))
        throw 'Type relation: duplicate input types in ' + raw.name;
      seen.set(key,true);
      result.push(row.copy());
    }
    result.sort((a,b)->Reflect.compare(
      [for (t in a) typeName(t)].join(' '),
      [for (t in b) typeName(t)].join(' ')));
    return {name:raw.name,rows:result};
  }

  public static function decode(name:String, raw:Array<Array<String>>):RelationContract
    return validate({name:name,rows:[for (row in raw) parseRow(row)]});

  public static function fromNumeric(name:String):Null<RelationContract> {
    var internal:String=switch(name) {
      case 'Div' | 'Add' | 'Sub' | 'Mul': numeric.NumericRelation.modernName(name);
      case _: return null;
    };
    var rows=[for (r in numeric.NumericRelation.rows(internal))
      [r.left,r.right,r.result]];
    return validate({name:name,rows:rows});
  }

  public static function select(name:String, declarations:StringMap<RelationContract>)
      :RelationContract {
    var declared=declarations.get(name);
    if (declared != null) return declared;
    var builtin=fromNumeric(name);
    if (builtin != null) return builtin;
    throw 'Type relation: missing declaration for ' + name;
  }

  public static function arity(contract:RelationContract):Int {
    if (contract == null || contract.rows.length == 0)
      throw 'Type relation: empty contract';
    return contract.rows[0].length - 1;
  }

  public static function result(contract:RelationContract, inputs:Array<NType>):NType {
    var n=arity(contract);
    if (inputs.length != n)
      throw 'Type error: ' + contract.name + ' requires ' + n + ' arguments';
    for (row in contract.rows) {
      var match=true;
      for (i in 0...n)
        if (!Type.enumEq(inputs[i],row[i])) {match=false;break;}
      if (match) return row[n];
    }
    var names:Array<String>=[];
    for (item in inputs) {
      var label='?';
      try label=typeName(item) catch (_:Dynamic) {}
      names.push(label);
    }
    throw 'Type error: no ' + contract.name + ' instance for '
      + names.join(' ') + '; explicit conversion required';
  }

  public static function signature(contract:RelationContract):String {
    var n=arity(contract);
    var vars=[for (i in 0...n+1) String.fromCharCode(97+i)];
    return contract.name + ' ' + vars.join(' ') + ' => ' + vars.join(' -> ');
  }

  /** The canonical ABI is independent of row declaration order and retains
      both arity and result types; no type information is silently erased. */
  public static function abiSignature(contract:RelationContract):String {
    var safe=validate(contract);
    return 'relation:' + safe.name + '/' + arity(safe) + ':'
      + [for (row in safe.rows)
        [for (item in row) typeName(item)].join(',')].join(';');
  }
}
