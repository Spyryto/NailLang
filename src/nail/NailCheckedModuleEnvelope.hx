package nail;

import haxe.Json;
import haxe.crypto.Sha256;
import haxe.ds.StringMap;
import nail.Value;

/**
 * Isolated transport preview for the *single-transaction* Nail
 * TCVerifiedModulePreview. A digest detects accidental/casual byte changes;
 * it is NOT a signature, authorization, attestation, proof of type soundness
 * or permission to execute. ModuleLinker must not consume this format.
 *
 * Only arrays and strings are used in the wire grammar:
 * [format, checkedInterface, encodedBytecode, digest].
 */
class NailCheckedModuleEnvelope {
  public static inline var FORMAT="naillang.checked-module.preview.v0";
  public static inline var MAX_NODES=50000;
  public static inline var MAX_DEPTH=128;

  static function fail(message:String):Dynamic
    throw "Nail checked module preview: "+message;

  static function listValues(items:Value,limit:Int):Array<Value> {
    var out:Array<Value>=[];
    var remaining=items;
    while(true) switch(remaining) {
      case Nil: return out;
      case Cons(first,rest):
        if(out.length>=limit) fail("too many list elements");
        out.push(first);
        remaining=rest;
      case _: fail("malformed Syntax list");
    }
    return out;
  }

  static function writeTree(value:Value,depth:Int,nodes:Array<Int>):Dynamic {
    if(depth>MAX_DEPTH || ++nodes[0]>MAX_NODES)
      fail("Syntax size or depth limit");
    return switch(value) {
      case SyntaxLeaf(tag,text):
        if(tag.length==0 || tag.length>128 || text.length>100000)
          fail("invalid Syntax leaf bounds");
        ["leaf",tag,text];
      case SyntaxNode(tag,children):
        if(tag.length==0 || tag.length>128)
          fail("invalid Syntax node tag");
        ["node",tag,[for(x in listValues(children,MAX_NODES))
          writeTree(x,depth+1,nodes)]];
      case _: fail("only Syntax bytecode trees can be transported");
    };
  }

  static function tree(raw:Dynamic,depth:Int,nodes:Array<Int>):Void {
    if(depth>MAX_DEPTH || ++nodes[0]>MAX_NODES)
      fail("bytecode size or depth limit");
    if(!Std.isOfType(raw,Array)) fail("invalid bytecode tree");
    var a:Array<Dynamic>=cast raw;
    if(a.length!=3 || !Std.isOfType(a[0],String)
      || !Std.isOfType(a[1],String))
      fail("invalid bytecode Syntax constructor");
    var kind:String=cast a[0],tag:String=cast a[1];
    if(tag.length==0 || tag.length>128) fail("invalid bytecode tag");
    switch(kind) {
      case "leaf":
        if(!Std.isOfType(a[2],String))
          fail("invalid bytecode leaf text");
        var value:String=cast a[2];
        if(value.length>100000) fail("bytecode leaf exceeds limit");
      case "node":
        if(!Std.isOfType(a[2],Array))
          fail("invalid bytecode child list");
        var children:Array<Dynamic>=cast a[2];
        if(children.length>MAX_NODES) fail("bytecode children exceed limit");
        for(child in children) tree(child,depth+1,nodes);
      case _: fail("unknown bytecode Syntax constructor");
    }
  }

  static function nodeParts(value:Dynamic,tag:String):Array<Dynamic> {
    if(!Std.isOfType(value,Array)) fail("expected "+tag+" Syntax");
    var a:Array<Dynamic>=cast value;
    if(a.length!=3 || a[0]!="node" || a[1]!=tag
      || !Std.isOfType(a[2],Array))
      fail("expected "+tag+" Syntax");
    return cast a[2];
  }

  static function leafText(value:Dynamic,kind:String):String {
    if(!Std.isOfType(value,Array)) fail("expected "+kind+" leaf");
    var a:Array<Dynamic>=cast value;
    if(a.length!=3 || a[0]!="leaf" || a[1]!=kind
      || !Std.isOfType(a[2],String))
      fail("expected "+kind+" leaf");
    return StringTools.trim(cast a[2]);
  }

  static function bytecodeDefinitions(bytecode:Dynamic):StringMap<Int> {
    var forms=nodeParts(bytecode,"Bytecode");
    if(forms.length>MAX_NODES) fail("too many bytecode forms");
    var found=new StringMap<Int>();
    for(form in forms) {
      if(!Std.isOfType(form,Array))
        fail("invalid top-level bytecode instruction");
      var op:Array<Dynamic>=cast form;
      if(op.length!=3 || op[0]!="node"
        || !Std.isOfType(op[1],String))
        fail("invalid top-level opcode");
      var tag=StringTools.trim(cast(op[1],String));
      if(tag=="DEFINE") {
        var args=nodeParts(form,cast op[1]);
        if(args.length!=2) fail("invalid DEFINE arity");
        var name=leafText(args[0],"Name");
        // Every real, exported symbol must have one unambiguous provider.
        if(found.exists(name)) fail("duplicate compiled definition "+name);
        nodeParts(args[1],"Code");
        found.set(name,1);
      } else if(tag=="EVAL") {
        var args=nodeParts(form,cast op[1]);
        if(args.length!=1) fail("invalid EVAL arity");
        nodeParts(args[0],"Code");
      } else fail("invalid top-level bytecode opcode "+tag);
    }
    return found;
  }

  static function contents(interfaceRaw:Dynamic,bytecode:Dynamic):Void {
    NailRowInterfacePreview.validate(interfaceRaw);
    tree(bytecode,0,[0]);
    var names=bytecodeDefinitions(bytecode);
    var envelope:Array<Dynamic>=cast interfaceRaw;
    var exports:Array<Dynamic>=cast envelope[1];
    for(e in exports) {
      var pair:Array<Dynamic>=cast e;
      var name:String=cast pair[0];
      if(!names.exists(name))
        fail("export has no compiled provider definition: "+name);
    }
  }

  static function payload(interfaceRaw:Dynamic,bytecode:Dynamic):Array<Dynamic>
    return [FORMAT,interfaceRaw,bytecode];

  static function digest(data:Array<Dynamic>):String
    return Sha256.encode(Json.stringify(data));

  /** Only accept the paired result from a *successful* Nail compiler
      transaction. No caller-supplied signature or arbitrary bytecode. */
  public static function encode(verified:Value):String {
    var pair:Array<Value>=switch(verified) {
      case SyntaxNode("TCVerifiedModulePreview",children):
        listValues(children,2);
      case _: fail("expected compiler-produced module preview");
    };
    if(pair.length!=2) fail("invalid compiler witness arity");
    var interfaceRaw:Dynamic=Json.parse(NailRowInterfacePreview.encode(pair[0]));
    var bytecode=writeTree(pair[1],0,[0]);
    contents(interfaceRaw,bytecode);
    var signed=payload(interfaceRaw,bytecode);
    return Json.stringify([FORMAT,interfaceRaw,bytecode,digest(signed)]);
  }

  /** Compare a freshly compiled program with a validated provider witness.
      No received bytecode is decoded as an executable Value or run here. */
  public static function codeMatches(envelope:String,compiled:Value):Bool {
    var payload:Array<Dynamic>=cast decode(envelope);
    return Json.stringify(payload[2])==Json.stringify(writeTree(compiled,0,[0]));
  }

  /** Validate canonical transport bytes and structural export-code pairing.
      A hash alone never establishes provider authenticity or trust. */
  public static function decode(source:String):Dynamic {
    var data:Dynamic=null;
    try data=Json.parse(source)
    catch(_:Dynamic) fail("invalid JSON");
    if(!Std.isOfType(data,Array)) fail("invalid module envelope");
    var a:Array<Dynamic>=cast data;
    if(a.length!=4 || a[0]!=FORMAT
      || !Std.isOfType(a[3],String))
      fail("invalid checked module format");
    contents(a[1],a[2]);
    var claimed:String=cast a[3];
    if(!~/^[0-9a-f]{64}$/.match(claimed))
      fail("invalid SHA-256 digest");
    if(digest(payload(a[1],a[2]))!=claimed)
      fail("checked module digest mismatch");
    if(Json.stringify(a)!=source)
      fail("noncanonical checked module JSON");
    return a;
  }
}
