package nail;

import haxe.Json;
import nail.Value;

/** Strict reference-only multi-export wrapper around independently
    validated row-scheme wire previews. Never used by public ModuleImage,
    ModuleLinker, or runtime type inference. */
class NailRowInterfacePreview {
  public static inline var FORMAT="naillang.interface.preview.v0";
  public static inline var MAX_EXPORTS=128;
  static final identifier=~/^[A-Za-z_][A-Za-z_0-9]*$/;

  static function fail(message:String):Dynamic
    throw "Nail interface preview: "+message;

  static function elements(value:Value):Array<Value> {
    var result:Array<Value>=[];
    var rest=value;
    while(true) switch(rest) {
      case Nil: return result;
      case Cons(head,tail):
        if (result.length>=MAX_EXPORTS) fail("too many interface definitions");
        result.push(head);
        rest=tail;
      case _: fail("invalid Syntax children");
    }
    return result;
  }

  /** Only serializes the canonical Nail IR and invokes strict validation.
      No sorting, type inference, or row-lacks reconstruction occurs here. */
  public static function encode(value:Value):String {
    var exported:Value=switch(value) {
      case SyntaxNode('TCWireInterface',
          Cons(SyntaxNode('TCWireExports',entries),Nil)): entries;
      case _: fail("invalid canonical interface Syntax");
    };
    var out:Array<Dynamic>=[];
    for(binding in elements(exported)) {
      switch(binding) {
        case SyntaxNode('TCBinding',
            Cons(SyntaxLeaf('TCName',name),Cons(scheme,Nil))):
          out.push([StringTools.trim(name),Json.parse(
            NailRowEvidenceAdapter.encode(scheme))]);
        case _: fail("invalid canonical interface binding");
      }
    }
    var data:Dynamic=[FORMAT,out];
    validate(data);
    return Json.stringify(data);
  }

  public static function validate(raw:Dynamic):Void {
    if (!Std.isOfType(raw,Array)) fail("invalid interface envelope");
    var image:Array<Dynamic>=cast raw;
    if (image.length!=2 || image[0]!=FORMAT)
      fail("invalid interface format");
    if (!Std.isOfType(image[1],Array))
      fail("invalid interface definitions");
    var entries:Array<Dynamic>=cast image[1];
    if (entries.length==0 || entries.length>MAX_EXPORTS)
      fail("invalid interface definition count");
    var previous:Null<String>=null;
    for(entry in entries) {
      if (!Std.isOfType(entry,Array)) fail("invalid interface entry");
      var pair:Array<Dynamic>=cast entry;
      if (pair.length!=2 || !Std.isOfType(pair[0],String))
        fail("invalid interface entry");
      var name:String=cast pair[0];
      if (!identifier.match(name)) fail("invalid interface definition name");
      if (previous!=null && Reflect.compare(previous,name)>=0)
        fail("noncanonical or duplicate interface definitions");
      previous=name;
      // The independent single-scheme validator rejects free variable
      // IDs, missing or invalid row-lacks constraints and malformed kinds.
      RowSchemePreview.validate(pair[1]);
    }
  }

  public static function decode(source:String):Dynamic {
    var parsed:Dynamic=null;
    try parsed=Json.parse(source)
    catch (_:Dynamic) fail("invalid JSON");
    validate(parsed);
    if (Json.stringify(parsed)!=source)
      fail("noncanonical JSON representation");
    return parsed;
  }

  // Decode a strictly validated portable preview into the private Syntax
  // IR understood by Nail. This is only a structural mapping: the Haxe
  // adapter may not infer, generalize, instantiate or authorize any type.
  static function valueList(items:Array<Value>):Value {
    var out:Value=Nil;
    var i=items.length;
    while (i>0) {
      i--;
      out=Cons(items[i],out);
    }
    return out;
  }

  static function syntaxNode(tag:String,children:Array<Value>):Value
    return SyntaxNode(tag,valueList(children));

  static function syntaxLeaf(tag:String,text:String):Value
    return SyntaxLeaf(tag,text);

  static function previewVar(id:Int):Value
    return syntaxLeaf("TCVar","#wire_import_"+id);

  static function decodeType(raw:Dynamic,depth:Int):Value {
    if (depth>RowSchemePreview.MAX_DEPTH)
      fail("import type depth limit exceeded");
    var input:Array<Dynamic>=cast raw;
    var tag:String=cast input[0];
    return switch(tag) {
      case "Int" | "Ratio" | "Float" | "Number" | "Exact"
        | "Bool" | "Text" | "Syntax":
        syntaxLeaf("TCBase",tag);
      case "var":
        previewVar(cast input[1]);
      case "fn":
        syntaxNode("TCFun",[
          decodeType(input[1],depth+1),
          decodeType(input[2],depth+1)]);
      case "list":
        syntaxNode("TCList",[decodeType(input[1],depth+1)]);
      case "row":
        var fields:Array<Dynamic>=cast input[1];
        if (input[2]==null) {
          var closed:Array<Value>=[];
          for (field in fields) {
            var pair:Array<Dynamic>=cast field;
            closed.push(syntaxNode("TCField",[
              syntaxLeaf("TCName",cast pair[0]),
              decodeType(pair[1],depth+1)]));
          }
          syntaxNode("TCStruct",closed);
        } else {
          var tail:Array<Dynamic>=cast input[2];
          var result:Value=previewVar(cast tail[1]);
          var i=fields.length;
          while (i>0) {
            i--;
            var pair:Array<Dynamic>=cast fields[i];
            result=syntaxNode("TCRowField",[
              syntaxLeaf("TCName",cast pair[0]),
              decodeType(pair[1],depth+1),result]);
          }
          result;
        }
      case _:
        // The preview wire validator accepts some syntax-independent
        // constructors that the Nail HM row importer does not yet handle.
        fail("unsupported imported type tag "+tag);
    };
  }

  static function decodeScheme(raw:Dynamic):Value {
    RowSchemePreview.validate(raw);
    var parts:Array<Dynamic>=cast raw;
    var quant:Array<Dynamic>=cast parts[2];
    var eq:Array<Dynamic>=cast parts[3];
    var lacks:Array<Dynamic>=cast parts[4];
    var qualifiers:Array<Value>=[];
    for (item in lacks) {
      var pair:Array<Dynamic>=cast item;
      var names:Array<Dynamic>=cast pair[1];
      var absent:Array<Value>=[];
      for (name in names)
        absent.push(syntaxLeaf("TCName",cast name));
      qualifiers.push(syntaxNode("TCWireLacks",[
        previewVar(cast pair[0]),
        syntaxNode("TCWireAbsent",absent)]));
    }
    return syntaxNode("TCWireScheme",[
      decodeType(parts[1],0),
      syntaxNode("TCWireQuant",[for (id in quant) previewVar(cast id)]),
      syntaxNode("TCWireEq",[for (id in eq) previewVar(cast id)]),
      syntaxNode("TCWireLacksSet",qualifiers)]);
  }

  /** An untrusted wire image is validated before conversion to private
      Syntax, but that does *not* attest its provider or runtime behavior. */
  public static function decodeSyntax(source:String):Value {
    var envelope:Array<Dynamic>=cast decode(source);
    var entries:Array<Dynamic>=cast envelope[1];
    var bindings:Array<Value>=[];
    for (entry in entries) {
      var pair:Array<Dynamic>=cast entry;
      bindings.push(syntaxNode("TCBinding",[
        syntaxLeaf("TCName",cast pair[0]),
        decodeScheme(pair[1])]));
    }
    return syntaxNode("TCWireInterface",[
      syntaxNode("TCWireExports",bindings)]);
  }
}
