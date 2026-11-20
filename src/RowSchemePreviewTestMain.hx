import haxe.Json;
import haxe.ds.StringMap;
import nail.Parser;
import nail.TypeChecker;
import nail.RowSchemePreview;
import nail.NailRowEvidenceAdapter;
import nail.NailRowInterfacePreview;
import nail.NailCheckedModuleEnvelope;
import nail.NailPinnedProviderRebuild;
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


    // The entire Nail checker environment is available at the successful
    // terminal continuation, but only source-level definitions are returned.
    // A failed *later* form never returns a partial environment or scheme.
    var transactionSource='nail 0.54 ; '
      +'def readText r = textConcat ( r . x ) " suffix " ;';
    var transactional=dogfood.invoke('tcCheckSourceSchemes',
      Text(transactionSource));
    eq(ResultValue.tag(transactional),ResultValue.OK,
      'Nail HM transaction accepts source before publishing schemes');
    var inferredScheme:Value=switch (ResultValue.get(
      transactional,ResultValue.OK)) {
      case SyntaxNode('TCCheckedSchemes',
          Cons(SyntaxNode('TCChecked',_),
            Cons(SyntaxNode('TCExportSchemes',
              Cons(SyntaxNode('TCBinding',
                Cons(SyntaxLeaf('TCName','readText'),
                  Cons(scheme,Nil))),Nil)),Nil))):
        scheme;
      case _: throw 'ROW SCHEME PREVIEW: unexpected transactional evidence';
    };
    eq(ResultValue.tag(dogfood.invoke(
      'tcCheckSource',Text(transactionSource))),ResultValue.OK,
      'legacy checked-source API remains valid');
    var legacyPayload=ResultValue.get(dogfood.invoke(
      'tcCheckSource',Text(transactionSource)),ResultValue.OK);
    ok(switch(legacyPayload) {
      case SyntaxNode('TCChecked',_): true;
      case _: false;
    },'legacy TCChecked payload shape is unchanged');
    var exported=dogfood.invoke('tcCanonicalRowEvidence',inferredScheme);
    eq(ResultValue.tag(exported),ResultValue.OK,
      'Nail reuses already inferred TCScheme for canonicalization');
    eq(NailRowEvidenceAdapter.encode(ResultValue.get(exported,ResultValue.OK)),
      canonicalFromHaxe,
      'checked Nail source scheme agrees with Haxe reference producer');

    var secondSource='nail 0.54 ; '
      +'def id x = x ; def readText r = '
      +'textConcat ( r . x ) " suffix " ;';
    var second=dogfood.invoke('tcCheckSourceSchemes',Text(secondSource));
    eq(ResultValue.tag(second),ResultValue.OK,
      'transactional environment contains multiple explicit definitions');
    var secondNames:Array<String>=switch(ResultValue.get(second,ResultValue.OK)) {
      case SyntaxNode('TCCheckedSchemes',
          Cons(_,Cons(SyntaxNode('TCExportSchemes',items),Nil))):
        var found:Array<String>=[];
        var rest=items;
        while (true) switch(rest) {
          case Nil: break;
          case Cons(SyntaxNode('TCBinding',
              Cons(SyntaxLeaf('TCName',name),Cons(_,Nil))),tail):
            found.push(name);
            rest=tail;
          case _: throw 'ROW SCHEME PREVIEW: malformed transaction exports';
        }
        found;
      case _: throw 'ROW SCHEME PREVIEW: expected transactional node';
    };
    eq(secondNames,['id','readText'],
      'only source definitions exported, no generated/private bindings');

    var invalidAfterDefinition='nail 0.54 ; '
      +'def ephemeral x = x ; 1 + 1.0 ;';
    var failed=dogfood.invoke('tcCheckSourceSchemes',
      Text(invalidAfterDefinition));
    eq(ResultValue.tag(failed),ResultValue.ERR,
      'later type error atomically rejects all inferred source schemes');
    var failedFollowup=dogfood.invoke('tcCheckSourceSchemes',
      Text(transactionSource));
    eq(ResultValue.tag(failedFollowup),ResultValue.OK,
      'a failed transaction cannot poison a later valid check');
    var missing=dogfood.run('nail 0.54 ; '
      +'tcCanonicalCheckedDefinition '
      +'" nail 0.54 ; def readField r = r . x ; " '
      +'" missing " ;');
    eq(missing.length,1,'unknown export probe returns one result');
    eq(ResultValue.tag(missing[0]),ResultValue.ERR,
      'checked source cannot export an absent definition');
    var directlyChecked=dogfood.run('nail 0.54 ; '
      +'tcCanonicalCheckedDefinition '
      +'" nail 0.54 ; def readField r = r . x ; " '
      +'" readField " ;');
    eq(directlyChecked.length,1,'checked source canonical probe returns once');
    eq(ResultValue.tag(directlyChecked[0]),ResultValue.OK,
      'one-pass checked source canonicalizes a named definition');
    eq(NailRowEvidenceAdapter.encode(
      ResultValue.get(directlyChecked[0],ResultValue.OK)),
      checked('nail 0.54 ; def readField r = r . x ;',"readField"),
      'direct checked source canonical output agrees with Haxe');


    // A selected interface is a complete transaction over Nail's already
    // inferred source-level schemes. Selection order is not wire order.
    var ifaceSource='nail 0.54 ; '
      +'def id x = x ; def readField r = r . x ;';
    function interfacePreview(source:String,names:String):Value {
      var expression='nail 0.54 ; tcCanonicalCheckedInterface '
        +'" '+source+' " '+names+' ;';
      var results=dogfood.run(expression);
      eq(results.length,1,'interface preview returns exactly one result');
      return results[0];
    }
    var orderA=interfacePreview(ifaceSource,
      '[ " readField " , " id " ]');
    var orderB=interfacePreview(ifaceSource,
      '[ " id " , " readField " ]');
    eq(ResultValue.tag(orderA),ResultValue.OK,
      'selected interface is constructed after complete typecheck');
    eq(ResultValue.tag(orderB),ResultValue.OK,
      'opposite selection order is also valid');
    var interfaceJSON=NailRowInterfacePreview.encode(
      ResultValue.get(orderA,ResultValue.OK));
    eq(interfaceJSON,NailRowInterfacePreview.encode(
      ResultValue.get(orderB,ResultValue.OK)),
      'selected interface is independent of request order');
    var expectedInterface=Json.stringify([
      NailRowInterfacePreview.FORMAT,
      [
        ['id',Json.parse(checked(ifaceSource,'id'))],
        ['readField',Json.parse(checked(ifaceSource,'readField'))]
      ]
    ]);
    eq(interfaceJSON,expectedInterface,
      'Nail multi-definition interface matches two Haxe checked schemes');
    eq(Json.stringify(NailRowInterfacePreview.decode(interfaceJSON)),
      interfaceJSON,'interface wire validates and roundtrips exactly');

    var reversedSource='nail 0.54 ; '
      +'def readField r = r . x ; def id x = x ;';
    eq(NailRowInterfacePreview.encode(ResultValue.get(
      interfacePreview(reversedSource,'[ " id " , " readField " ]'),
      ResultValue.OK)),interfaceJSON,
      'source definition order does not alter canonical preview');

    for (invalid in [
      {names:'[ " id " , " id " ]',reason:'Duplicate'},
      {names:'[ " notThere " ]',reason:'No verified'},
      {names:'[ " #private " ]',reason:'Invalid'},
      {names:'[ " invalid-name " ]',reason:'Invalid'},
      {names:'[]',reason:'Empty'}
    ]) {
      var rejected=interfacePreview(ifaceSource,invalid.names);
      eq(ResultValue.tag(rejected),ResultValue.ERR,
        'invalid interface selection rejects: '+invalid.reason);
      var message=Std.string(RuntimeValues.toPlain(
        ResultValue.get(rejected,ResultValue.ERR)));
      ok(message.indexOf(invalid.reason)>=0,
        'interface rejection diagnostic contains '+invalid.reason);
    }

    var invalidProgram=interfacePreview(
      'nail 0.54 ; def id x = x ; 1 + 1.0 ;','[ " id " ]');
    eq(ResultValue.tag(invalidProgram),ResultValue.ERR,
      'type failure after definition publishes no partial interface');
    var afterFailure=interfacePreview(ifaceSource,'[ " id " ]');
    eq(ResultValue.tag(afterFailure),ResultValue.OK,
      'failed interface typecheck leaves subsequent requests unaffected');

    var imageBadOrder=Json.parse(interfaceJSON);
    var reversedEntries:Array<Dynamic>=cast(cast imageBadOrder:Array<Dynamic>)[1];
    reversedEntries.reverse();
    checkFails(() -> NailRowInterfacePreview.validate(imageBadOrder),
      'noncanonical or duplicate');
    var imageDuplicate=Json.parse(interfaceJSON);
    var duplicatedEntries:Array<Dynamic>=cast(cast imageDuplicate:Array<Dynamic>)[1];
    duplicatedEntries[1]=duplicatedEntries[0];
    checkFails(() -> NailRowInterfacePreview.validate(imageDuplicate),
      'noncanonical or duplicate');
    var imageWrongScheme=Json.parse(interfaceJSON);
    var wrongEntries:Array<Dynamic>=cast(cast imageWrongScheme:Array<Dynamic>)[1];
    var firstEntry:Array<Dynamic>=cast wrongEntries[0];
    firstEntry[1]=['untrusted'];
    checkFails(() -> NailRowInterfacePreview.validate(imageWrongScheme),
      'invalid format');
    checkFails(() -> NailRowInterfacePreview.decode(' '+interfaceJSON),
      'noncanonical JSON');
    checkFails(() -> NailRowInterfacePreview.decode(
      '{"format":"not-an-interface"}'),'invalid interface envelope');


    // Opt-in typed value exports reuse the already parsed export directive
    // while preserving its existing macro-module semantics outside this API.
    // Export directives are removed prior to ordinary macro expansion; only
    // full-program success authorizes the selected source definitions.
    function declaredPreview(source:String):Value {
      return dogfood.invoke('tcCanonicalDeclaredInterface',Text(source));
    }
    var declaredSource='nail 0.54 ; '
      +'def id x = x ; export id ; '
      +'def readField r = r . x ; export readField ;';
    var declared=declaredPreview(declaredSource);
    eq(ResultValue.tag(declared),ResultValue.OK,
      'explicit value exports are accepted only by the opt-in preview');
    eq(NailRowInterfacePreview.encode(
      ResultValue.get(declared,ResultValue.OK)),interfaceJSON,
      'source-declared exports match checked selected interface');

    var declaredBefore='nail 0.54 ; '
      +'export readField ; export id ; '
      +'def readField r = r . x ; def id x = x ;';
    var beforeResult=declaredPreview(declaredBefore);
    eq(ResultValue.tag(beforeResult),ResultValue.OK,
      'export declarations may precede verified definitions');
    eq(NailRowInterfacePreview.encode(
      ResultValue.get(beforeResult,ResultValue.OK)),interfaceJSON,
      'declaration order does not affect canonical public preview');

    var onlyId=declaredPreview('nail 0.54 ; '
      +'def id x = x ; export id ; def readField r = r . x ;');
    eq(ResultValue.tag(onlyId),ResultValue.OK,
      'non-exported definitions may still be checked internally');
    var onlyIdData:Array<Dynamic>=cast Json.parse(
      NailRowInterfacePreview.encode(ResultValue.get(onlyId,ResultValue.OK)));
    var selected:Array<Dynamic>=cast onlyIdData[1];
    eq(selected.length,1,'only explicitly exported names appear');
    eq((cast selected[0]:Array<Dynamic>)[0],'id',
      'unlisted name does not leak from type environment');

    for (invalid in [
      {source:'nail 0.54 ; def id x = x ;',why:'No typed value exports'},
      {source:'nail 0.54 ; def id x = x ; export id ; export id ;',
        why:'Duplicate typed value export'},
      {source:'nail 0.54 ; export unseen ; def id x = x ;',
        why:'No verified interface definition'},
      {source:'nail 0.54 ; def id x = x ; export id ; 1 + 1.0 ;',
        why:''}
    ]) {
      var invalidResult=declaredPreview(invalid.source);
      eq(ResultValue.tag(invalidResult),ResultValue.ERR,
        'bad declared interface must return Error atomically');
      if(invalid.why!='') {
        var diagnostic=Std.string(RuntimeValues.toPlain(
          ResultValue.get(invalidResult,ResultValue.ERR)));
        ok(diagnostic.indexOf(invalid.why)>=0,
          'declared interface failure contains: '+invalid.why);
      }
    }
    eq(ResultValue.tag(declaredPreview(declaredSource)),ResultValue.OK,
      'failed declared-interface transaction does not pollute later checks');
    eq(ResultValue.tag(dogfood.invoke('tcCheckSource',
      Text(declaredSource))),ResultValue.ERR,
      'ordinary checked-source API still refuses value export directives');


    // Import a validated *portable preview*, then let Nail reconstitute
    // each TCScheme. The importer may not borrow its own internal type
    // variables across two instantiations, nor drop TCRowQuant negatives.
    var wireSyntax=NailRowInterfacePreview.decodeSyntax(interfaceJSON);
    var importedResult=dogfood.invoke('tcImportWireInterface',wireSyntax);
    eq(ResultValue.tag(importedResult),ResultValue.OK,
      'canonical wire preview becomes a private imported Nail interface');
    var imported:Value=ResultValue.get(importedResult,ResultValue.OK);
    ok(switch(imported) {
      case SyntaxNode('TCImportedInterface',
          Cons(SyntaxNode('TCImportedSchemes',_),Nil)): true;
      case _: false;
    },'imported interface is a closed private HM scheme table');
    function importRequest(table:Value,name:String,seed:String):Value {
      return SyntaxNode('TCImportRequest',Cons(table,
        Cons(SyntaxLeaf('TCName',name),
          Cons(SyntaxNode('TCSubstitutions',Nil),
            Cons(SyntaxLeaf('TCSeed',seed),Nil)))));
    }
    var readRequest=importRequest(imported,'readField','#import_one');
    var one=dogfood.invoke('tcImportWireInstantiate',readRequest);
    eq(ResultValue.tag(one),ResultValue.OK,
      'Nail instantiates the imported row-polymorphic type');
    var firstInstance=ResultValue.get(one,ResultValue.OK);
    var nextSeed:String=switch(firstInstance) {
      case SyntaxNode('TCInferResult',
          Cons(_,Cons(_,Cons(SyntaxLeaf('TCSeed',seed),Nil)))): seed;
      case _: throw 'ROW SCHEME PREVIEW: missing HM seed after import';
    };
    var two=dogfood.invoke('tcImportWireInstantiate',
      importRequest(imported,'readField',nextSeed));
    eq(ResultValue.tag(two),ResultValue.OK,
      'second imported use instantiates with a threaded fresh seed');
    var typeA:Value=switch(firstInstance) {
      case SyntaxNode('TCInferResult',Cons(ty,_)): ty;
      case _: throw 'ROW SCHEME PREVIEW: first import has no type';
    };
    var typeB:Value=switch(ResultValue.get(two,ResultValue.OK)) {
      case SyntaxNode('TCInferResult',Cons(ty,_)): ty;
      case _: throw 'ROW SCHEME PREVIEW: second import has no type';
    };
    ok(Json.stringify(RuntimeValues.toPlain(typeA))
      !=Json.stringify(RuntimeValues.toPlain(typeB)),
      'independent uses cannot share the same fresh row/type variables');

    function rowFieldValue(name:String):Value {
      return SyntaxNode('TCRowField',Cons(SyntaxLeaf('TCName',name),
        Cons(SyntaxLeaf('TCBase','Int'),
          Cons(SyntaxNode('TCStruct',Nil),Nil))));
    }
    function tailProbe(table:Value,label:String):Value {
      return dogfood.invoke('tcImportWireProbeTailBinding',
        SyntaxNode('TCImportTailProbe',Cons(
          importRequest(table,'readField','#tail_probe'),
          Cons(rowFieldValue(label),Nil))));
    }
    eq(ResultValue.tag(tailProbe(imported,'x')),ResultValue.ERR,
      'known imported x field remains forbidden inside its row tail');
    eq(ResultValue.tag(tailProbe(imported,'z')),ResultValue.OK,
      'fresh unrelated z field is allowed in the imported row tail');

    var augmented:Dynamic=Json.parse(interfaceJSON);
    var wrapped:Array<Dynamic>=cast augmented;
    var entries:Array<Dynamic>=cast wrapped[1];
    var foundExtra=false;
    for (item in entries) {
      var pair:Array<Dynamic>=cast item;
      if (pair[0]=='readField') {
        var scheme:Array<Dynamic>=cast pair[1];
        var guards:Array<Dynamic>=cast scheme[4];
        var guard:Array<Dynamic>=cast guards[0];
        guard[1]=['reserved','x'];
        foundExtra=true;
      }
    }
    ok(foundExtra,'readField export has a quantified open-row guard');
    var extraWire=Json.stringify(augmented);
    var augmentedSyntax=NailRowInterfacePreview.decodeSyntax(extraWire);
    var importedExtra=dogfood.invoke('tcImportWireInterface',augmentedSyntax);
    eq(ResultValue.tag(importedExtra),ResultValue.OK,
      'additional negative-only row-lacks survives wire import');
    var extraTable=ResultValue.get(importedExtra,ResultValue.OK);
    eq(ResultValue.tag(tailProbe(extraTable,'reserved')),ResultValue.ERR,
      'late duplicate reserved is rejected from extra wire row-lacks');
    eq(ResultValue.tag(tailProbe(extraTable,'x')),ResultValue.ERR,
      'ordinary prefix field x is still forbidden after import');
    eq(ResultValue.tag(tailProbe(extraTable,'z')),ResultValue.OK,
      'row tail remains open to genuinely new fields');

    // Strict decode and Nail scheme import are separate gates.
    var tampered:Dynamic=Json.parse(extraWire);
    var malformed:Array<Dynamic>=cast tampered;
    var malformedExports:Array<Dynamic>=cast malformed[1];
    var forged:Array<Dynamic>=cast malformedExports[1];
    var forgedScheme:Array<Dynamic>=cast forged[1];
    forgedScheme[4]=[];
    checkFails(() -> NailRowInterfacePreview.decodeSyntax(
      Json.stringify(tampered)),'missing row-lacks qualifier');
    var missingImported=dogfood.invoke('tcImportWireInstantiate',
      importRequest(imported,'absent','#missing_import'));
    eq(ResultValue.tag(missingImported),ResultValue.ERR,
      'unknown imported name is rejected without defaulting to a builtin');

    // Eq evidence must travel through the same imported quantifier map:
    // a primitive comparable Int is valid; a function value is not.
    var eqOnlyJSON=Json.stringify([
      NailRowInterfacePreview.FORMAT,[
        ['onlyEq',[RowSchemePreview.FORMAT,
          ['fn',['var',0],['var',0]],[0],[0],[]]]
      ]]);
    var eqImportedResult=dogfood.invoke('tcImportWireInterface',
      NailRowInterfacePreview.decodeSyntax(eqOnlyJSON));
    eq(ResultValue.tag(eqImportedResult),ResultValue.OK,
      'strict preview importer accepts an ordinary Eq scheme');
    var eqTable=ResultValue.get(eqImportedResult,ResultValue.OK);
    var eqRequest=importRequest(eqTable,'onlyEq','#eq_probe');
    function eqProbe(candidate:Value):Value {
      return dogfood.invoke('tcImportWireProbeEquality',
        SyntaxNode('TCImportEqProbe',Cons(eqRequest,
          Cons(candidate,Nil))));
    }
    eq(ResultValue.tag(eqProbe(SyntaxLeaf('TCBase','Int'))),
      ResultValue.OK,'imported Eq qualifier allows comparable Int');
    eq(ResultValue.tag(eqProbe(SyntaxNode('TCFun',Cons(
      SyntaxLeaf('TCBase','Int'),
      Cons(SyntaxLeaf('TCBase','Int'),Nil))))),
      ResultValue.ERR,'imported Eq qualifier rejects function values');



    // Provider-side evidence must be emitted in the SAME successful
    // parse/expand/check/compile transaction as executable Bytecode.
    // A manually provided wire signature alone is not this witness.
    var providerSource='nail 0.54 ; '
      +'def id x = x ; export id ; '
      +'def readField r = r . x ; export readField ;';
    var compiledProvider=dogfood.invoke('tcCompileDeclaredModulePreview',
      Text(providerSource));
    eq(ResultValue.tag(compiledProvider),ResultValue.OK,
      'Nail compiles a typed provider and its exports atomically');
    var providerInterface:Value=Nil;
    var providerBytecode:Value=Nil;
    switch(ResultValue.get(compiledProvider,ResultValue.OK)) {
      case SyntaxNode('TCVerifiedModulePreview',
          Cons(interfaceTree,Cons(SyntaxNode('Bytecode',ops),Nil))):
        providerInterface=interfaceTree;
        providerBytecode=SyntaxNode('Bytecode',ops);
      case _:
        throw 'ROW SCHEME PREVIEW: expected interface + executable Bytecode';
    }
    eq(NailRowInterfacePreview.encode(providerInterface),
      interfaceJSON,'compiled provider exports exact canonical checked interface');

    var executableSource='nail 0.54 ; '
      +'def id x = x ; def readField r = r . x ;';
    var independentCompilation=dogfood.invoke('tcCompileCheckedSource',
      Text(executableSource));
    eq(ResultValue.tag(independentCompilation),ResultValue.OK,
      'reference checked compiler accepts the same executable definitions');
    eq(Json.stringify(RuntimeValues.toPlain(providerBytecode)),
      Json.stringify(RuntimeValues.toPlain(
        ResultValue.get(independentCompilation,ResultValue.OK))),
      'provider witness Bytecode matches independently checked compilation');

    function badProvider(source:String,label:String):Void {
      var response=dogfood.invoke('tcCompileDeclaredModulePreview',Text(source));
      eq(ResultValue.tag(response),ResultValue.ERR,
        'provider publishes no type/code pair for '+label);
    }
    badProvider('nail 0.54 ; def id x = x ;',
      'missing export directives');
    badProvider('nail 0.54 ; def id x = x ; export id ; export id ;',
      'duplicate exports');
    badProvider('nail 0.54 ; def id x = x ; export absent ;',
      'unknown export');
    badProvider('nail 0.54 ; def id x = x ; export id ; 1 + 1.0 ;',
      'later type mismatch');
    badProvider('nail 0.54 ; def id x = x ; '
      +'export id ; def missing = notDefined ;',
      'late unresolved name');
    eq(ResultValue.tag(dogfood.invoke('tcCompileDeclaredModulePreview',
      Text(providerSource))),ResultValue.OK,
      'a failed provider transaction cannot poison a later valid provider');


    // The portable envelope binds the exact interface and code emitted
    // by one successful local Nail compiler invocation. This is a content
    // integrity check, NOT a signature or a typecheck of remote bytecode.
    var providerWitness=ResultValue.get(compiledProvider,ResultValue.OK);
    var checkedEnvelope=NailCheckedModuleEnvelope.encode(providerWitness);
    var decodedEnvelope:Array<Dynamic>=cast
      NailCheckedModuleEnvelope.decode(checkedEnvelope);
    eq(decodedEnvelope[0],NailCheckedModuleEnvelope.FORMAT,
      'checked module preview has explicit unreleased version');
    eq(Json.stringify(decodedEnvelope),checkedEnvelope,
      'checked module envelope roundtrips byte-for-byte');
    eq(decodedEnvelope[1],Json.parse(interfaceJSON),
      'checked module carries independently verified row interface');
    var repeatedEnvelope=NailCheckedModuleEnvelope.encode(
      ResultValue.get(dogfood.invoke('tcCompileDeclaredModulePreview',
        Text(providerSource)),ResultValue.OK));
    eq(repeatedEnvelope,checkedEnvelope,
      'same checked source produces deterministic digest and bytes');
    var separateOrder='nail 0.54 ; '
      +'export readField ; export id ; '
      +'def id x = x ; def readField r = r . x ;';
    eq(NailCheckedModuleEnvelope.encode(ResultValue.get(
      dogfood.invoke('tcCompileDeclaredModulePreview',
        Text(separateOrder)),ResultValue.OK)),checkedEnvelope,
      'export directive order cannot change checked provider digest');

    var damagedHash:Dynamic=Json.parse(checkedEnvelope);
    var altered:Array<Dynamic>=cast damagedHash;
    altered[3]="0000000000000000000000000000000000000000000000000000000000000000";
    checkFails(() -> NailCheckedModuleEnvelope.decode(
      Json.stringify(damagedHash)),'digest mismatch');

    var damagedInterface:Dynamic=Json.parse(checkedEnvelope);
    var outer:Array<Dynamic>=cast damagedInterface;
    var image:Array<Dynamic>=cast outer[1];
    var imageExports:Array<Dynamic>=cast image[1];
    var idEntry:Array<Dynamic>=cast imageExports[0];
    var changedScheme:Array<Dynamic>=cast idEntry[1];
    changedScheme[1]=['fn',['Int'],['Int']];
    changedScheme[2]=[];
    checkFails(() -> NailCheckedModuleEnvelope.decode(
      Json.stringify(damagedInterface)),'digest mismatch');

    var damagedCode:Dynamic=Json.parse(checkedEnvelope);
    var codeOuter:Array<Dynamic>=cast damagedCode;
    var tree:Array<Dynamic>=cast codeOuter[2];
    var forms:Array<Dynamic>=cast tree[2];
    var firstForm:Array<Dynamic>=cast forms[0];
    var secondForm:Array<Dynamic>=cast forms[1];
    var firstChildren:Array<Dynamic>=cast firstForm[2];
    var secondChildren:Array<Dynamic>=cast secondForm[2];
    var temporary=firstChildren[1];
    firstChildren[1]=secondChildren[1];
    secondChildren[1]=temporary;
    checkFails(() -> NailCheckedModuleEnvelope.decode(
      Json.stringify(damagedCode)),'digest mismatch');

    // A claimed signature cannot supply a missing definition even if
    // a host creates a syntactically plausible fake TCVerifiedModulePreview.
    var missingCode:Value=SyntaxNode('Bytecode',
      Cons(SyntaxNode('EVAL',Cons(SyntaxNode('Code',Nil),Nil)),Nil));
    var fakePair=SyntaxNode('TCVerifiedModulePreview',
      Cons(providerInterface,Cons(missingCode,Nil)));
    checkFails(() -> NailCheckedModuleEnvelope.encode(fakePair),
      'export has no compiled provider definition');
    checkFails(() -> NailCheckedModuleEnvelope.decode(
      ' '+checkedEnvelope),'noncanonical checked module JSON');


    // A digest carried by an untrusted envelope is not provenance.
    // The embedding host must instead pin the source and bootstrap image
    // independently, then recompile in a fresh no-capabilities Nail VM.
    var pinnedSourceDigest=haxe.crypto.Sha256.encode(providerSource);
    var pinnedCompilerDigest=haxe.crypto.Sha256.encode(
      haxe.Resource.getString('bootstrap_image'));
    NailPinnedProviderRebuild.verify(providerSource,
      pinnedSourceDigest,pinnedCompilerDigest,checkedEnvelope);
    ok(true,'independently pinned source/compiler reproduce provider bytes');

    var invalidSourceDigest='00000000000000000000000000000000'
      +'00000000000000000000000000000000';
    checkFails(() -> NailPinnedProviderRebuild.verify(providerSource,
      invalidSourceDigest,pinnedCompilerDigest,checkedEnvelope),
      'trusted source digest mismatch');
    checkFails(() -> NailPinnedProviderRebuild.verify(providerSource,
      pinnedSourceDigest,invalidSourceDigest,checkedEnvelope),
      'trusted compiler image digest mismatch');

    // Even if an attacker recomputes SHA-256 for a modified but canonical
    // bytecode tree, the pinned source's independently rebuilt bytes differ.
    var substituted:Dynamic=Json.parse(checkedEnvelope);
    var received:Array<Dynamic>=cast substituted;
    var receivedTree:Array<Dynamic>=cast received[2];
    var receivedForms:Array<Dynamic>=cast receivedTree[2];
    var define0:Array<Dynamic>=cast receivedForms[0];
    var define1:Array<Dynamic>=cast receivedForms[1];
    var define0Children:Array<Dynamic>=cast define0[2];
    var define1Children:Array<Dynamic>=cast define1[2];
    var swap=define0Children[1];
    define0Children[1]=define1Children[1];
    define1Children[1]=swap;
    received[3]=haxe.crypto.Sha256.encode(
      Json.stringify([received[0],received[1],received[2]]));
    var rehashedEnvelope=Json.stringify(received);
    NailCheckedModuleEnvelope.decode(rehashedEnvelope);
    ok(true,'attacker-rehashed envelope still passes integrity alone');
    checkFails(() -> NailPinnedProviderRebuild.verify(providerSource,
      pinnedSourceDigest,pinnedCompilerDigest,rehashedEnvelope),
      'differs from pinned source build');

    // The source pin is not silently replaced by the received source.
    var alternate='nail 0.54 ; def id x = x ; export id ;';
    checkFails(() -> NailPinnedProviderRebuild.verify(alternate,
      pinnedSourceDigest,pinnedCompilerDigest,checkedEnvelope),
      'trusted source digest mismatch');

    trace('Row scheme preview: '+checks+' portable, strict checks passed');
  }
}
