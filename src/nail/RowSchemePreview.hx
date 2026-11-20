package nail;

import haxe.Json;
import haxe.ds.IntMap;
import haxe.ds.StringMap;

/** Reference-only wire validator for the *unreleased* structural-row ABI.
    It is intentionally not used by ModuleImage, ModuleLinker or the public
    type checker. No source syntax, bytecode or VM semantics change here.

    Canonical JSON consists exclusively of ordered arrays:
      [format, term, [quantifiers], [eqQuantifiers], [[tail, [absentNames]]...]]
    Types are ["Int"], ["var", 0], ["fn", a, b], ["list", a], etc.;
    a row is ["row", [["x", ["Int"]], ...], ["var", 0] | null].
    Quantifiers are 0..n-1 in order, and names / qualifiers are sorted.
    This preview *validates* canonical input; a future compiler must own
    alpha-renaming, proof obligations and canonical type construction. */
class RowSchemePreview {
  public static inline var FORMAT = "naillang.row-scheme.preview.v0";
  public static inline var MAX_DEPTH = 48;
  public static inline var MAX_NODES = 2048;
  public static inline var MAX_QUANTIFIERS = 64;
  public static inline var MAX_FIELDS = 128;

  static final identifier = ~/^[A-Za-z_][A-Za-z_0-9]*$/;

  static function fail(message:String):Dynamic
    throw "Row scheme preview: " + message;

  static function list(raw:Dynamic,role:String):Array<Dynamic> {
    if (!Std.isOfType(raw,Array)) fail("invalid " + role);
    return cast raw;
  }

  static function intValue(raw:Dynamic,role:String):Int {
    if (!Std.isOfType(raw,Int)) fail("invalid " + role);
    var id:Int=cast raw;
    if (id<0) fail("invalid " + role);
    return id;
  }

  static function name(raw:Dynamic):String {
    if (!Std.isOfType(raw,String)) fail("invalid field name");
    var value:String=cast raw;
    if (!identifier.match(value)) fail("invalid field name");
    return value;
  }

  static function variable(raw:Dynamic,n:Int,used:IntMap<Bool>,
      role:String):Int {
    var value=list(raw,role);
    if (value.length!=2 || value[0]!="var")
      fail("invalid "+role);
    var id=intValue(value[1],role);
    if (id>=n) fail("free row/type variable");
    used.set(id,true);
    return id;
  }

  static function typeTerm(raw:Dynamic,depth:Int,budget:Array<Int>,
      n:Int,used:IntMap<Bool>,required:IntMap<StringMap<Bool>>):Void {
    if (depth>MAX_DEPTH || ++budget[0]>MAX_NODES)
      fail("type size limit exceeded");
    var node=list(raw,"type node");
    if (node.length==0 || !Std.isOfType(node[0],String))
      fail("invalid type node");
    var tag:String=cast node[0];
    switch (tag) {
      case "Int" | "Ratio" | "Float" | "Number" | "Exact"
        | "Bool" | "Text" | "Syntax":
        if (node.length!=1) fail("invalid primitive type");
      case "var":
        variable(node,n,used,"type variable");
      case "list" | "vector":
        if (node.length!=2) fail("invalid collection type");
        typeTerm(node[1],depth+1,budget,n,used,required);
      case "fn":
        if (node.length!=3) fail("invalid function type");
        typeTerm(node[1],depth+1,budget,n,used,required);
        typeTerm(node[2],depth+1,budget,n,used,required);
      case "row":
        if (node.length!=3) fail("invalid structural row");
        var fields=list(node[1],"row fields");
        if (fields.length==0 || fields.length>MAX_FIELDS)
          fail("invalid row field count");
        var tail:Null<Int>=null;
        if (node[2]!=null)
          tail=variable(node[2],n,used,"row tail");
        var previous:Null<String>=null;
        for (field in fields) {
          var pair=list(field,"row field");
          if (pair.length!=2) fail("invalid row field");
          var label=name(pair[0]);
          if (previous!=null && Reflect.compare(previous,label)>=0)
            fail("noncanonical row field order or duplicate label");
          previous=label;
          typeTerm(pair[1],depth+1,budget,n,used,required);
          if (tail!=null) {
            var names=required.get(tail);
            if (names==null) {
              names=new StringMap<Bool>();
              required.set(tail,names);
            }
            names.set(label,true);
          }
        }
      case _:
        fail("unsupported type tag "+tag);
    }
  }

  /** Reject unscoped variables, phantom quantifiers, noncanonical field
      order, missing row-lacks obligations and malformed constraint lists.
      The preview is not capable of providing or verifying a public ABI. */
  public static function validate(raw:Dynamic):Void {
    var envelope=list(raw,"envelope");
    if (envelope.length!=5 || envelope[0]!=FORMAT)
      fail("invalid format");
    var q=list(envelope[2],"quantifiers");
    if (q.length>MAX_QUANTIFIERS) fail("too many quantifiers");
    for (i in 0...q.length)
      if (intValue(q[i],"quantifier")!=i)
        fail("noncanonical quantifier order");

    var used=new IntMap<Bool>();
    var required=new IntMap<StringMap<Bool>>();
    typeTerm(envelope[1],0,[0],q.length,used,required);
    for (i in 0...q.length)
      if (!used.exists(i)) fail("unused quantifier");

    var eq=list(envelope[3],"Eq qualifiers");
    var previousEq=-1;
    for (item in eq) {
      var id=intValue(item,"Eq qualifier");
      if (id>=q.length || id<=previousEq)
        fail("noncanonical Eq qualifiers");
      previousEq=id;
    }

    var lacks=list(envelope[4],"row-lacks qualifiers");
    var previousTail=-1;
    var seen=new IntMap<Bool>();
    for (entry in lacks) {
      var pair=list(entry,"row-lacks entry");
      if (pair.length!=2) fail("invalid row-lacks entry");
      var tail=intValue(pair[0],"row-lacks tail");
      if (tail>=q.length) fail("free row/type variable");
      if (tail<=previousTail) fail("noncanonical row-lacks tail order");
      previousTail=tail;
      if (!required.exists(tail)) fail("orphan row-lacks tail");
      seen.set(tail,true);
      var absent=list(pair[1],"row-lacks names");
      if (absent.length==0 || absent.length>MAX_FIELDS)
        fail("invalid row-lacks field count");
      var observed=new StringMap<Bool>();
      var previousName:Null<String>=null;
      for (item in absent) {
        var label=name(item);
        if (previousName!=null && Reflect.compare(previousName,label)>=0)
          fail("noncanonical row-lacks field order or duplicate label");
        observed.set(label,true);
        previousName=label;
      }
      for (field in required.get(tail).keys())
        if (!observed.exists(field)) fail("missing row-lacks obligation "+field);
    }
    for (tail in required.keys())
      if (!seen.exists(tail)) fail("missing row-lacks qualifier");
  }

  /** Produces a byte-stable, array-only canonical JSON image. */
  public static function encode(raw:Dynamic):String {
    validate(raw);
    return Json.stringify(raw);
  }

  /** Rejects whitespace/alternate escape spellings as noncanonical text. */
  public static function decode(text:String):Dynamic {
    var value:Dynamic=null;
    try value=Json.parse(text)
    catch (error:Dynamic) fail("invalid JSON");
    validate(value);
    if (Json.stringify(value)!=text)
      fail("noncanonical JSON representation");
    return value;
  }
}
