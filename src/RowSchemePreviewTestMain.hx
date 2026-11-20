import haxe.Json;
import haxe.ds.StringMap;
import nail.Parser;
import nail.TypeChecker;
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

  static function checked(source:String,name:String):String {
    var parser=new Parser(source,new StringMap<Array<String>>());
    var checker=new TypeChecker();
    checker.checkParsed(parser,parser.parse());
    return checker.experimentalCheckedRowPreview(name);
  }

  static function checkFails(action:Void->Void,expected:String):Void {
    var message="";
    try action() catch (error:Dynamic) message=Std.string(error);
    ok(message.indexOf(expected)>=0,
      'expected "'+expected+'" got "'+message+'"');
  }

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
    var closed:Dynamic=[RowSchemePreview.FORMAT,
      ["row",[["answer",["Int"]]],null],[],[],[]];
    eq(RowSchemePreview.encode(RowSchemePreview.decode(
      RowSchemePreview.encode(closed))),RowSchemePreview.encode(closed),
      'closed structural rows need no row-lacks constraint');

    var sameTail:Dynamic=[RowSchemePreview.FORMAT,
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

    // A row tail is not an ordinary value-type variable or Eq-qualified
    // type variable. Old preview validation accepted these kind errors.
    var mixedKind=clone(example());
    setAt(at(mixedKind,1),2,["fn",["var",0],["var",1]]);
    fails(mixedKind,"row variable used as ordinary type");
    var eqRow=clone(example());
    setAt(eqRow,3,[0,1]);
    fails(eqRow,"Eq qualifier on row tail");

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
    var orphan:Dynamic=[RowSchemePreview.FORMAT,
      ["var",0],[0],[],[[0,["x"]]]];
    fails(orphan,'orphan row-lacks tail');

    var unsupported=clone(example());
    setAt(unsupported,1,["nominal","Person",["var",0]]);
    fails(unsupported,'unsupported type tag nominal');
    var invalidRow=clone(example());
    setAt(at(at(invalidRow,1),1),2,["fn",["Int"],["Int"]]);
    fails(invalidRow,'invalid row tail');
    var emptyOpenRow:Dynamic=[RowSchemePreview.FORMAT,
      ["row",[],["var",0]],[0],[],[[0,["x"]]]];
    fails(emptyOpenRow,'invalid row field count');
    var wrongFormat=clone(example());
    setAt(wrongFormat,0,'naillang.row-scheme.public.v1');
    fails(wrongFormat,'invalid format');
    var wrongArity=clone(example());
    (cast wrongArity:Array<Dynamic>).push("unexpected");
    fails(wrongArity,'invalid format');

    var nested:Dynamic=["Int"];
    for (i in 0...(RowSchemePreview.MAX_DEPTH+2))
      nested=["list",nested];
    fails([RowSchemePreview.FORMAT,nested,[],[],[]],
      'type size limit exceeded');
    badText(" "+canonical,'noncanonical JSON representation');
    badText(canonical+" ",'noncanonical JSON representation');
    badText("{\"format\":\"row-scheme\"}",'invalid envelope');
    badText("not-json",'invalid JSON');

    // A checked definition, not caller-supplied type metadata, is the
    // source of a proposed canonical producer image. The source checker
    // must have committed successfully before it can be requested.
    checkFails(() -> new TypeChecker().experimentalCheckedRowPreview("head"),
      "definition has not been source-checked");
    var readText='nail 0.54 ; '
      +'def readText r = textConcat ( r . x ) " suffix " ;';
    var expectedWire='["naillang.row-scheme.preview.v0",'
      +'["fn",["row",[["x",["Text"]]],["var",0]],["Text"]],'
      +'[0],[],[[0,["x"]]]]';
    var output=checked(readText,"readText");
    eq(output,expectedWire,"checked inferred open row has canonical wire evidence");
    eq(RowSchemePreview.encode(RowSchemePreview.decode(output)),output,
      "checked producer roundtrips through strict decoder");
    var shifted='nail 0.54 ; '
      +'def unused a = a ; '
      +'def readText r = textConcat ( r . x ) " suffix " ;';
    eq(checked(shifted,"readText"),output,
      "canonical image is independent of unrelated binder allocation");
    var xy='nail 0.54 ; '
      +'def readBoth r = textConcat ( r . x ) ( r . y ) ;';
    var yx='nail 0.54 ; '
      +'def readBoth r = textConcat ( r . y ) ( r . x ) ;';
    eq(checked(xy,"readBoth"),checked(yx,"readBoth"),
      "field order changes do not alter canonical inferred row scheme");

    var plain=checked('nail 0.54 ; def id x = x ;',"id");
    ok(plain.indexOf('["fn",["var",0],["var",0]]')>=0,
      "producer also canonicalizes a closed ordinary HM scheme");

    var parser=new Parser(readText,new StringMap<Array<String>>());
    var checker=new TypeChecker();
    checker.checkParsed(parser,parser.parse());
    checkFails(() -> checker.publicScheme("readText"),
      "experimental open rows cannot be exported");
    var broken='nail 0.54 ; def wrong = if true then 1 else false ;';
    checkFails(() -> checked(broken,"wrong"),"cannot unify");

    trace('Row scheme preview: '+checks+' portable, strict checks passed');
  }
}
