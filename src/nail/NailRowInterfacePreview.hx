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
}
