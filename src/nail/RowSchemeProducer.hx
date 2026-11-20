package nail;

import haxe.ds.IntMap;
import haxe.ds.StringMap;
import nail.NType;
import nail.TypeScheme;

/** Canonical wire producer for a *successfully inferred* Haxe HM definition.
    Called by TypeChecker.experimentalCheckedRowPreview only; NOT a module
    export, a type proof for a foreign provider, or a Nail-written ABI.
    Only constraints recoverable from checked type structure are emitted.
    Additional lacks obligations present only in the Nail checker ledger
    require a later, independently verified producer path. */
@:allow(nail.TypeChecker)
class RowSchemeProducer {
  final scheme:TypeScheme;
  final quantified=new IntMap<Bool>();
  final mapped=new IntMap<Int>();
  final used=new IntMap<Bool>();
  final lacks=new IntMap<StringMap<Bool>>();
  var nextId=0;
  var nodes=0;

  function new(scheme:TypeScheme) {
    this.scheme=scheme;
    if (scheme==null || scheme.term==null ||
        scheme.quantified==null || scheme.comparable==null ||
        scheme.quantified.length>RowSchemePreview.MAX_QUANTIFIERS)
      throw "Row scheme producer: invalid inferred scheme";
    for (id in scheme.quantified) {
      if (id<0 || quantified.exists(id))
        throw "Row scheme producer: duplicate or invalid quantifier";
      quantified.set(id,true);
    }
  }

  function variable(id:Int):Int {
    if (!quantified.exists(id))
      throw "Row scheme producer: free type variable";
    used.set(id,true);
    var current=mapped.get(id);
    if (current!=null) return current;
    var fresh=nextId++;
    mapped.set(id,fresh);
    return fresh;
  }

  function charge(depth:Int):Void {
    if (depth>RowSchemePreview.MAX_DEPTH ||
        ++nodes>RowSchemePreview.MAX_NODES)
      throw "Row scheme producer: type size limit exceeded";
  }

  function row(type:NType,depth:Int):Dynamic {
    var fields:Array<nail.NType.StructuralField>=[];
    var seen=new StringMap<Bool>();
    var current=type;
    var tail:Dynamic=null;
    var steps=0;
    while (true) {
      if (++steps>RowSchemePreview.MAX_DEPTH)
        throw "Row scheme producer: row chain too deep";
      switch(current) {
        case TStructural(items):
          for (field in items) fields.push(field);
          current=null;
        case TOpenStructural(items,rest):
          for (field in items) fields.push(field);
          current=rest;
        case TVariable(id):
          var index=variable(id);
          tail=["var",index];
          current=null;
        case _:
          throw "Row scheme producer: invalid structural row tail";
      }
      if (current==null) break;
    }
    if (fields.length==0 || fields.length>RowSchemePreview.MAX_FIELDS)
      throw "Row scheme producer: invalid structural row width";
    fields.sort((a,b)->Reflect.compare(a.name,b.name));
    var result:Array<Dynamic>=[];
    var previous:Null<String>=null;
    for (field in fields) {
      if (field==null || field.name==null ||
          (previous!=null && Reflect.compare(previous,field.name)>=0))
        throw "Row scheme producer: duplicate structural field";
      previous=field.name;
      result.push([field.name,term(field.type,depth+1)]);
      if (tail!=null) {
        var pair:Array<Dynamic>=cast tail;
        var index:Int=cast pair[1];
        var blocked=lacks.get(index);
        if (blocked==null) {
          blocked=new StringMap<Bool>();
          lacks.set(index,blocked);
        }
        blocked.set(field.name,true);
      }
    }
    return ["row",result,tail];
  }

  function term(type:NType,depth:Int):Dynamic {
    charge(depth);
    return switch(type) {
      case TInt: ["Int"];
      case TRatio: ["Ratio"];
      case TFloat: ["Float"];
      case TNumber: ["Number"];
      case TExact: ["Exact"];
      case TBoolean: ["Bool"];
      case TText: ["Text"];
      case TSyntax: ["Syntax"];
      case TVariable(id): ["var",variable(id)];
      case TFunction(a,b): ["fn",term(a,depth+1),term(b,depth+1)];
      case TList(x): ["list",term(x,depth+1)];
      case TVector(x): ["vector",term(x,depth+1)];
      case TStructural(_) | TOpenStructural(_,_): row(type,depth);
      case TRecord(_) | TRecordApplied(_,_) | TSum(_,_):
        throw "Row scheme producer: nominal type ABI unsupported";
    };
  }

  function encode():String {
    var type=term(scheme.term,0);
    if (nextId!=scheme.quantified.length)
      throw "Row scheme producer: unused quantified variable";
    var eq:Array<Int>=[];
    var comparable=new IntMap<Bool>();
    for (id in scheme.comparable) {
      if (!quantified.exists(id) || comparable.exists(id))
        throw "Row scheme producer: invalid Eq qualifier";
      comparable.set(id,true);
      eq.push(variable(id));
    }
    eq.sort((a,b)->a-b);
    var tails:Array<Dynamic>=[];
    for (id in 0...nextId) {
      var missing=lacks.get(id);
      if (missing!=null) {
        var fields=[for (name in missing.keys()) name];
        fields.sort(Reflect.compare);
        tails.push([id,fields]);
      }
    }
    var ids:Array<Int>=[for (id in 0...nextId) id];
    // The strict decoder also checks the variable kinds and all negative
    // row-field obligations against the emitted structural prefixes.
    return RowSchemePreview.encode(
      [RowSchemePreview.FORMAT,type,ids,eq,tails]);
  }

  static function encodeInferred(scheme:TypeScheme):String {
    return new RowSchemeProducer(scheme).encode();
  }
}
