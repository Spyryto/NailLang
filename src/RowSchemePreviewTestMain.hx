import haxe.Json;
import haxe.ds.StringMap;
import nail.Parser;
import nail.TypeChecker;
import nail.RowSchemePreview;
import nail.NailRowEvidenceAdapter;
import nail.BootRuntime;
import nail.ResultValue;
import nail.Value;
import nail.RuntimeValues;

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

    // A rejected later form must not make earlier definitions eligible for
    // attestation: the ordinary checker commits only whole programs.
    var failingSource='nail 0.54 ; def ephemeral x = x ; '
      +'if true then 1 else false ;';
    var failingParser=new Parser(failingSource,new StringMap<Array<String>>());
    var failingChecker=new TypeChecker();
    checkFails(() -> failingChecker.checkParsed(
      failingParser,failingParser.parse()),"cannot unify");
    checkFails(() -> failingChecker.experimentalCheckedRowPreview("ephemeral"),
      "definition has not been source-checked");


    // Dogfood the Nail-written HM scheme/row-qualifier computation.
    // Haxe below only converts the canonical Syntax shape to JSON; it
    // must not sort fields, infer types, or manufacture lacks evidence.
    var dogfood=new BootRuntime(60000000);
    function nailEvidence(expression:String):Value {
      var results=dogfood.run('nail 0.54 ; '+expression+' ;');
      eq(results.length,1,'Nail canonical row producer returns one result');
      ok(ResultValue.tag(results[0])==ResultValue.OK,
        'Nail canonical row producer accepts valid scheme');
      return ResultValue.get(results[0],ResultValue.OK);
    }
    function nailRejects(expression:String,fragment:String):Void {
      var results=dogfood.run('nail 0.54 ; '+expression+' ;');
      eq(results.length,1,'Nail canonical row rejects once');
      eq(ResultValue.tag(results[0]),ResultValue.ERR,
        'Nail canonical producer rejects malformed scheme');
      var diagnostic=RuntimeValues.toPlain(
        ResultValue.get(results[0],ResultValue.ERR));
      ok(Std.string(diagnostic).indexOf(fragment)>=0,
        'Nail row rejection contains '+fragment);
    }

    var rowScheme='tcCanonicalRowEvidence ( tcGeneralize '
      +'( tcFun ( tcRowField " x " ( tcBase " Text " ) '
      +'( tcVar " rho " ) ) ( tcBase " Text " ) ) [] [] )';
    var canonicalFromNail=NailRowEvidenceAdapter.encode(
      nailEvidence(rowScheme));
    var canonicalFromHaxe=checked('nail 0.54 ; '
      +'def readText r = textConcat ( r . x ) " suffix " ;',"readText");
    eq(canonicalFromNail,canonicalFromHaxe,
      'Nail dogfooded HM scheme matches Haxe checked-source wire preview');
    // Tail and value-type variables are different kinds. Compare exact
    // canonical IDs for a fully polymorphic structural projection.
    var genericAccessor='tcCanonicalRowEvidence ( tcGeneralize '
      +'( tcFun ( tcRowField " x " ( tcVar " a " ) '
      +'( tcVar " rho " ) ) ( tcVar " a " ) ) [] [] )';
    var genericHaxe=checked('nail 0.54 ; '
      +'def takeX r = r . x ;',"takeX");
    eq(NailRowEvidenceAdapter.encode(nailEvidence(genericAccessor)),
      genericHaxe,'Nail/Haxe canonical ID order agrees for row tails and field types');

    var leftFirst='tcCanonicalRowEvidence ( tcSchemeWithRows '
      +'( tcFun ( tcRowField " x " ( tcBase " Text " ) '
      +'( tcRowField " y " ( tcBase " Int " ) ( tcVar " r " ) ) ) '
      +'( tcBase " Text " ) ) [ tcVar " r " ] [] [] )';
    var rightFirst='tcCanonicalRowEvidence ( tcSchemeWithRows '
      +'( tcFun ( tcRowField " y " ( tcBase " Int " ) '
      +'( tcRowField " x " ( tcBase " Text " ) ( tcVar " r " ) ) ) '
      +'( tcBase " Text " ) ) [ tcVar " r " ] [] [] )';
    eq(NailRowEvidenceAdapter.encode(nailEvidence(leftFirst)),
      NailRowEvidenceAdapter.encode(nailEvidence(rightFirst)),
      'Nail canonicalizes opposite row-field order itself');

    // TCRowQuant can retain a negative obligation not visible in the
    // function's type. The Nail-produced image must carry both names.
    var extraLacks='tcCanonicalRowEvidence ( tcSchemeWithRows '
      +'( tcFun ( tcRowField " x " ( tcBase " Text " ) '
      +'( tcVar " r " ) ) ( tcBase " Int " ) ) '
      +'[ tcVar " r " ] [] '
      +'[ tcRowField " reserved " ( tcBase " Bool " ) '
      +'( tcVar " r " ) ] )';
    var emitted=NailRowEvidenceAdapter.encode(nailEvidence(extraLacks));
    ok(emitted.indexOf('[[0,["reserved","x"]]]')>=0,
      'Nail preserves extra negative TCRowQuant evidence');

    var duplicate='tcCanonicalRowEvidence ( tcSchemeWithRows '
      +'( tcRowField " x " ( tcBase " Int " ) '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " r " ) ) ) '
      +'[ tcVar " r " ] [] [] )';
    nailRejects(duplicate,'Duplicate');
    var overlap='tcCanonicalRowEvidence ( tcSchemeWithRows '
      +'( tcFun ( tcRowField " x " ( tcBase " Int " ) '
      +'( tcVar " r " ) ) ( tcVar " r " ) ) '
      +'[ tcVar " r " ] [] [] )';
    nailRejects(overlap,'ordinary');
    var orphan='tcCanonicalRowEvidence ( tcSchemeWithRows '
      +'( tcVar " r " ) [ tcVar " r " ] [] '
      +'[ tcRowField " absent " ( tcBase " Int " ) ( tcVar " r " ) ] )';
    nailRejects(orphan,'outside');
    var eqOnTail='tcCanonicalRowEvidence ( tcSchemeWithRows '
      +'( tcRowField " x " ( tcBase " Text " ) ( tcVar " r " ) ) '
      +'[ tcVar " r " ] [ tcVar " r " ] [] )';
    nailRejects(eqOnTail,'Eq qualifier');
    var freeVar='tcCanonicalRowEvidence ( tcSchemeWithRows '
      +'( tcFun ( tcVar " a " ) ( tcVar " a " ) ) [] [] [] )';
    nailRejects(freeVar,'Free variable');

    trace('Row scheme preview: '+checks+' portable, strict checks passed');
  }
}
