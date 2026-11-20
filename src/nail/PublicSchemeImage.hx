package nail;

import nail.NType;
import nail.TypeScheme;

/** Portable, checked type schemes for independently compiled public exports.
    The existing printable signature remains the link ABI. Structured type
    metadata is necessary only for compiling consumers without provider
    source; it must agree with the signed/canonical interface string.
    This metadata is NOT proof of authenticity: trust/signature gates apply
    to distribution of module images. */
class PublicSchemeImage {
  public static inline var MAX_DEPTH=48;
  public static inline var MAX_NODES=2048;

  static function encodeType(type:NType, depth:Int, budget:Array<Int>):Dynamic {
    if (depth>MAX_DEPTH || ++budget[0]>MAX_NODES)
      throw 'Public scheme image: type size limit exceeded';
    return switch (type) {
      case TNumber: ['Number'];
      case TExact: ['Exact'];
      case TInt: ['Int'];
      case TRatio: ['Ratio'];
      case TFloat: ['Float'];
      case TBoolean: ['Bool'];
      case TText: ['Text'];
      case TSyntax: ['Syntax'];
      case TVariable(id): ['var',id];
      case TList(x): ['list',encodeType(x,depth+1,budget)];
      case TVector(x): ['vector',encodeType(x,depth+1,budget)];
      case TFunction(a,b): ['fn',encodeType(a,depth+1,budget),
        encodeType(b,depth+1,budget)];
      case TStructural(fields): ['struct',[for (f in fields)
        {name:f.name,type:encodeType(f.type,depth+1,budget)}]];
      case TOpenStructural(_, _):
        throw 'Public scheme image: open structural rows are experimental';
      case TRecord(name): ['record',name];
      case TRecordApplied(name,items): ['applied',name,
        [for (t in items) encodeType(t,depth+1,budget)]];
      case TSum(name,items): ['sum',name,
        [for (t in items) encodeType(t,depth+1,budget)]];
    };
  }

  static function requireList(value:Dynamic, expected:String):Array<Dynamic> {
    if (!Std.isOfType(value,Array))
      throw 'Public scheme image: invalid '+expected;
    return cast value;
  }

  static function requireText(value:Dynamic):String {
    if (!Std.isOfType(value,String))
      throw 'Public scheme image: invalid type name';
    return cast value;
  }

  static function requireId(value:Dynamic):Int {
    if (!Std.isOfType(value,Int) || (cast value:Int)<0)
      throw 'Public scheme image: invalid type variable';
    return cast value;
  }

  static function decodeType(raw:Dynamic, depth:Int, budget:Array<Int>):NType {
    if (depth>MAX_DEPTH || ++budget[0]>MAX_NODES)
      throw 'Public scheme image: type size limit exceeded';
    var row=requireList(raw,'type node');
    if (row.length==0) throw 'Public scheme image: invalid type node';
    var tag=requireText(row[0]);
    switch(tag) {
      case 'Number' | 'Exact' | 'Int' | 'Ratio' | 'Float' | 'Bool'
        | 'Text' | 'Syntax':
        if (row.length!=1) throw 'Public scheme image: invalid primitive';
        return switch(tag) {
          case 'Number': TNumber;
          case 'Exact': TExact;
          case 'Int': TInt;
          case 'Ratio': TRatio;
          case 'Float': TFloat;
          case 'Bool': TBoolean;
          case 'Text': TText;
          case 'Syntax': TSyntax;
          case _: throw 'Public scheme image: invalid primitive';
        };
      case 'var':
        if (row.length!=2) throw 'Public scheme image: invalid variable';
        return TVariable(requireId(row[1]));
      case 'list' | 'vector':
        if (row.length!=2) throw 'Public scheme image: invalid collection';
        var item=decodeType(row[1],depth+1,budget);
        return tag=='list' ? TList(item) : TVector(item);
      case 'fn':
        if (row.length!=3) throw 'Public scheme image: invalid function';
        return TFunction(decodeType(row[1],depth+1,budget),
          decodeType(row[2],depth+1,budget));
      case 'struct':
        if (row.length!=2) throw 'Public scheme image: invalid record';
        var fields=requireList(row[1],'structural fields');
        if (fields.length==0 || fields.length>128)
          throw 'Public scheme image: invalid structural fields';
        var result:Array<nail.NType.StructuralField>=[];
        for (f in fields) {
          if (f==null || !Std.isOfType(Reflect.field(f,'name'),String))
            throw 'Public scheme image: invalid structural field';
          result.push({name:cast Reflect.field(f,'name'),
            type:decodeType(Reflect.field(f,'type'),depth+1,budget)});
        }
        return TStructural(result);
      case 'record':
        if (row.length!=2) throw 'Public scheme image: invalid record';
        return TRecord(requireText(row[1]));
      case 'applied' | 'sum':
        if (row.length!=3) throw 'Public scheme image: invalid nominal type';
        var name=requireText(row[1]);
        var args=requireList(row[2],'type parameters');
        if (args.length>16) throw 'Public scheme image: excessive parameters';
        var values=[for (a in args) decodeType(a,depth+1,budget)];
        return tag=='sum' ? TSum(name,values) : TRecordApplied(name,values);
      case _:
        throw 'Public scheme image: invalid type tag '+tag;
    }
  }

  /** Only the checked public type API may produce or consume this metadata. */
  public static function encode(input:TypeScheme):Dynamic {
    var scheme=TypeChecker.validatePublicScheme(input,true);
    return {term:encodeType(scheme.term,0,[0]),
      quantified:scheme.quantified.copy(),
      comparable:scheme.comparable.copy()};
  }

  public static function decode(raw:Dynamic, signature:String):TypeScheme {
    if (raw==null || !Std.isOfType(Reflect.field(raw,'quantified'),Array)
        || !Std.isOfType(Reflect.field(raw,'comparable'),Array))
      throw 'Public scheme image: invalid scheme';
    // The current v3 module ABI has exactly these three scheme fields.
    // Silently ignoring an unrecognized row-lacks/qualification field
    // would turn a constrained polymorphic export into an unsound one.
    // A future ABI must explicitly version and validate new qualifiers.
    for (field in Reflect.fields(raw))
      if (field!='term' && field!='quantified' && field!='comparable')
        throw 'Public scheme image: unsupported scheme field '+field;
    var quantified=[for (id in requireList(Reflect.field(raw,'quantified'),
      'quantifiers')) requireId(id)];
    var comparable=[for (id in requireList(Reflect.field(raw,'comparable'),
      'constraints')) requireId(id)];
    var checked=TypeChecker.validatePublicScheme({
      term:decodeType(Reflect.field(raw,'term'),0,[0]),
      quantified:quantified,comparable:comparable
    },true);
    var checker=new TypeChecker();
    checker.importPublicScheme('_portable',checked,true);
    if (checker.signature('_portable')!=signature)
      throw 'Public scheme image: canonical signature mismatch';
    return checked;
  }
}
