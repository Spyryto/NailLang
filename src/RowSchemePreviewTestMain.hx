import haxe.Json;
import nail.RowSchemePreview;

/** Standalone cross-target tests for the *unreleased* row scheme preview.
    These are validation and canonically formatted wire-data tests, not
    public module import/export tests. */
class RowSchemePreviewTestMain {
  static var checks=0;

  static function ok(condition:Bool,label:String):Void {
    if (!condition) throw "ROW SCHEME PREVIEW: "+label;
    checks++;
  }

  static function eq(actual:Dynamic,expected:Dynamic,label:String):Void
    ok(Json.stringify(actual)==Json.stringify(expected),
      label+" expected "+Json.stringify(expected)+" got "+Json.stringify(actual));

  static function fails(raw:Dynamic,fragment:String):Void {
    var message="";
    try RowSchemePreview.encode(raw) catch (error:Dynamic) message=Std.string(error);
    ok(message.indexOf(fragment)>=0,
      'expected "'+fragment+'" got "'+message+'"');
  }

  static function badText(source:String,fragment:String):Void {
    var message="";
    try RowSchemePreview.decode(source) catch (error:Dynamic) message=Std.string(error);
    ok(message.indexOf(fragment)>=0,
      'expected "'+fragment+'" got "'+message+'"');
  }

  static function at(value:Dynamic,i:Int):Dynamic {
    var values:Array<Dynamic>=cast value;
    return values[i];
  }
  static function setAt(value:Dynamic,i:Int,child:Dynamic):Void {
    var values:Array<Dynamic>=cast value;
    values[i]=child;
  }
  static function clone(value:Dynamic):Dynamic
    return Json.parse(Json.stringify(value));

  static function example():Dynamic
    return [RowSchemePreview.FORMAT,
      ["fn",
        ["row",[["x",["Int"]],["y",["Text"]]],["var",0]],
        ["list",["var",1]]],
      [0,1],[1],[[0,["x","y"]]]];

  public static function main():Void {
    var canonical='["naillang.row-scheme.preview.v0",'
      +'["fn",["row",[["x",["Int"]],["y",["Text"]]],["var",0]],'
      +'["list",["var",1]]],[0,1],[1],[[0,["x","y"]]]]';
    eq(RowSchemePreview.encode(example()),canonical,
      'wire serialization is byte-for-byte deterministic');
    eq(RowSchemePreview.encode(RowSchemePreview.decode(canonical)),canonical,
      'exact canonical decoding and re-encoding');
    var closed=[RowSchemePreview.FORMAT,
      ["row",[["answer",["Int"]]],null],[],[],[]];
    eq(RowSchemePreview.encode(RowSchemePreview.decode(
      RowSchemePreview.encode(closed))),RowSchemePreview.encode(closed),
      'closed structural rows need no row-lacks constraint');

    var sameTail=[RowSchemePreview.FORMAT,
      ["fn",
        ["row",[["x",["Int"]]],["var",0]],
        ["row",[["y",["Bool"]]],["var",0]]],
      [0],[],[[0,["x","y"]]]];
    ok(RowSchemePreview.encode(sameTail).length>0,
      'shared tail combines obligations from both row prefixes');
    var missingShared=clone(sameTail);
    setAt(missingShared,4,[[0,["x"]]]);
    fails(missingShared,'missing row-lacks obligation y');

    var unordered=clone(example());
    setAt(at(at(unordered,1),1),1,
      [["y",["Text"]],["x",["Int"]]]);
    fails(unordered,'noncanonical row field order');
    var duplicated=clone(example());
    setAt(at(at(duplicated,1),1),1,
      [["x",["Int"]],["x",["Int"]]]);
    fails(duplicated,'duplicate label');
    var invalidName=clone(example());
    setAt(at(at(unordered,1),1),1,[["a-b",["Int"]]]);
    // Use a freshly cloned value: reordering has already invalidated above.
    setAt(at(at(invalidName,1),1),1,[["bad-name",["Int"]]]);
    fails(invalidName,'invalid field name');

    var free=clone(example());
    setAt(at(at(free,1),1),2,["var",4]);
    fails(free,'free row/type variable');
    var phantom=clone(example());
    setAt(phantom,2,[0,1,2]);
    fails(phantom,'unused quantifier');
    var nonCanonicalQuant=clone(example());
    setAt(nonCanonicalQuant,2,[1,0]);
    fails(nonCanonicalQuant,'noncanonical quantifier order');
    var badEq=clone(example());
    setAt(badEq,3,[1,1]);
    fails(badEq,'noncanonical Eq qualifiers');

    var noQual=clone(example());
    setAt(noQual,4,[]);
    fails(noQual,'missing row-lacks qualifier');
    var insufficient=clone(example());
    setAt(insufficient,4,[[0,["x"]]]);
    fails(insufficient,'missing row-lacks obligation y');
    var reversedLacks=clone(example());
    setAt(reversedLacks,4,[[0,["y","x"]]]);
    fails(reversedLacks,'noncanonical row-lacks field order');
    var extraQualifier=clone(example());
    setAt(extraQualifier,4,[[0,["x","y"]],[0,["z"]]]);
    fails(extraQualifier,'noncanonical row-lacks tail order');
    var orphan=[RowSchemePreview.FORMAT,
      ["var",0],[0],[],[[0,["x"]]]];
    fails(orphan,'orphan row-lacks tail');

    var unsupported=clone(example());
    setAt(unsupported,1,["nominal","Person",["var",0]]);
    fails(unsupported,'unsupported type tag nominal');
    var invalidRow=clone(example());
    setAt(at(at(invalidRow,1),1),2,["fn",["Int"],["Int"]]);
    fails(invalidRow,'invalid row tail');
    var emptyOpenRow=[RowSchemePreview.FORMAT,
      ["row",[],["var",0]],[0],[],[[0,["x"]]]];
    fails(emptyOpenRow,'invalid row field count');
    var wrongFormat=clone(example());
    setAt(wrongFormat,0,'naillang.row-scheme.public.v1');
    fails(wrongFormat,'invalid format');
    var wrongArity=clone(example());
    (cast wrongArity:Array<Dynamic>).push("unexpected");
    fails(wrongArity,'invalid format');

    var nested:Dynamic=["Int"];
    for (i in 0...RowSchemePreview.MAX_DEPTH+2)
      nested=["list",nested];
    fails([RowSchemePreview.FORMAT,nested,[],[],[]],
      'type size limit exceeded');
    badText(" "+canonical,'noncanonical JSON representation');
    badText(canonical+" ",'noncanonical JSON representation');
    badText("{\"format\":\"row-scheme\"}",'invalid envelope');
    badText("not-json",'invalid JSON');

    trace('Row scheme preview: '+checks+' portable, strict checks passed');
  }
}
