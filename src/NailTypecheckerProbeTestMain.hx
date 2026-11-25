import haxe.Json;
import haxe.ds.StringMap;
import nail.Parser;
import nail.MacroExpander;
import nail.SyntaxEncoder;
import nail.BootRuntime;
import nail.ResultValue;
import nail.Value;
import nail.TypeChecker;
import nail.NailSourceAnalysis;
import nail.NailMacroModuleInputs;

/** End-to-end differential tests for the first Nail-written HM checker.
    The Nail checker is invoked via the source-free bytecode VM; it has no
    Haxe type-checker callback or privileged type primitive. */
class NailTypecheckerProbeTestMain {
  static var checks:Int=0;
  static function eq(a:Dynamic,b:Dynamic,label:String):Void {
    if (Json.stringify(a)!=Json.stringify(b))
      throw 'NAIL TYPECHECKER: '+label+' expected '+Json.stringify(b)+' got '+Json.stringify(a);
    checks++;
  }

  /** Alpha-normalize generated Lambda binders; the two implementations
      intentionally use different fresh-name allocators. Free globals must
      still match byte-for-byte, so hygiene cannot be faked by renaming all
      private identifiers during comparison. */
  static function normalizedMacro(tree:Value,
      bindings:StringMap<String>,depth:Int):String {
    return switch (tree) {
      case SyntaxLeaf('Var',name):
        'Var('+(bindings.exists(name) ? bindings.get(name) : name)+')';
      case SyntaxNode('Lambda',
          Cons(SyntaxLeaf('Name',name),Cons(body,Nil))):
        var inner=bindings.copy();
        inner.set(name,'bound'+depth);
        'Lambda(bound'+depth+','+normalizedMacro(body,inner,depth+1)+')';
      case SyntaxLeaf(tag,text): tag+'('+Json.stringify(text)+')';
      case SyntaxNode(tag,items):
        tag+'('+normalizedMacro(items,bindings,depth)+')';
      case Cons(item,rest):
        normalizedMacro(item,bindings,depth)+','
          +normalizedMacro(rest,bindings,depth);
      case Nil: '[]';
      case _: 'Unexpected '+Std.string(tree);
    };
  }

  static function compareMacroExpansion(boot:BootRuntime,body:String):Void {
    var source='nail 0.54 ; '+body;
    var parsed=boot.invoke('modernRewrite',
      boot.invoke('parseSource',Text(source)));
    var original=MacroExpander.syntax(parsed);
    var nail=boot.invoke('nailMacroExpandSyntax',parsed);
    eq(switch(nail) { case SyntaxNode(tag,_): tag; case _: ''; },
      'Program','Nail expansion should be a Program');
    eq(normalizedMacro(nail,new StringMap<String>(),0),
      normalizedMacro(original,new StringMap<String>(),0),
      'Nail/Haxe hygienic macro AST alpha-equivalence: '+body);
    var hostChecked=boot.invoke('tcCheckSyntaxTraced',original);
    var nailChecked=boot.invoke('tcCheckSyntaxTraced',nail);
    eq(ResultValue.tag(nailChecked),ResultValue.tag(hostChecked),
      'Nail/Haxe macro type verdict parity: '+body);
    eq(ResultValue.tag(nailChecked),ResultValue.OK,
      'Nail hygienic macro expanded program typechecks: '+body);
    var fromSource=boot.invoke('tcCheckSourceNailMacrosTraced',Text(source));
    eq(ResultValue.tag(fromSource),ResultValue.OK,
      'self-hosted parsing, macro expansion and type inference: '+body);
  }

  static function compareImportedMacro(boot:BootRuntime,source:String,
      moduleSources:StringMap<String>, expected:Array<String>):Void {
    var reads=new StringMap<Int>();
    var resolver=(name:String) -> {
      var previous=reads.get(name);
      reads.set(name,previous == null ? 1 : previous+1);
      return moduleSources.get(name);
    };
    var prepared=boot.invoke('tcPrepareTypedSource',Text(source));
    eq(switch(prepared) {
      case SyntaxNode('TCPreparedMacros',_): true;
      case _: false;
    },true,'Nail typed parser prepares imported macro input');
    var program=switch(prepared) {
      case SyntaxNode('TCPreparedMacros',Cons(p,_)): p;
      case _: throw 'Expected prepared Nail module source';
    };
    var modules=NailMacroModuleInputs.collect(boot,source,resolver,program);
    for (name in reads.keys()) eq(reads.get(name),1,
      'transitive module fetched once: '+name);
    var request=NailMacroModuleInputs.request(program,modules);
    var ours=boot.invoke('nailMacroExpandWithModules',request);
    var theirs=MacroExpander.syntax(program,name -> {
      var input=moduleSources.get(name);
      return input == null ? null : NailMacroModuleInputs.parsedModern(boot,input);
    });
    eq(normalizedMacro(ours,new StringMap<String>(),0),
      normalizedMacro(theirs,new StringMap<String>(),0),
      'Nail vs Haxe imported macro Syntax alpha-equivalence');
    var check=boot.invoke('tcCheckSourceNailModulesTraced',
      SyntaxNode('NMSourceRequest',
        Cons(SyntaxLeaf('NMSource',source),Cons(modules,Nil))));
    eq(ResultValue.tag(check),ResultValue.OK,
      'Nail-only module expansion + Nail HM inference');
    var checkTypes=inspectResult(boot,boot.invoke('tcCheckExpandedTypedTraced',
      SyntaxNode('TCExpansionRequest',
        Cons(prepared,Cons(ours,Nil)))));
    eq(checkTypes.ok,true,'Nail-generated expanded Syntax checks');
    eq(checkTypes.types,expected,
      'Nail-owned macro module expansion has inferred types');
  }

  static function rejectImportedMacro(boot:BootRuntime,source:String,
      moduleSources:StringMap<String>):Void {
    var program=NailMacroModuleInputs.parsedModern(boot,source);
    var modules=NailMacroModuleInputs.collect(boot,source,
      name -> moduleSources.get(name),program);
    var ours=boot.invoke('nailMacroExpandWithModules',
      NailMacroModuleInputs.request(program,modules));
    var theirs=MacroExpander.syntax(program,name -> {
      var input=moduleSources.get(name);
      return input == null ? null : NailMacroModuleInputs.parsedModern(boot,input);
    });
    eq(switch(ours) {
      case SyntaxLeaf('MacroError',_): true;
      case _: false;
    },true,'Nail rejects bad macro module: '+source);
    eq(switch(theirs) {
      case SyntaxLeaf('MacroError',_): true;
      case _: false;
    },true,'Haxe rejects same bad macro module: '+source);
  }

  static function inspect(boot:BootRuntime,source:String):{ok:Bool,types:Array<String>,message:String} {
    return inspectResult(boot,boot.invoke('tcCheckSource',Text(source)));
  }

  /** Differential probe for already macro-expanded surface Syntax. This
      isolates Nail's HM checker from the Haxe macro expansion oracle. */
  static function inspectExpanded(boot:BootRuntime,source:String):{ok:Bool,types:Array<String>,message:String} {
    var parser=new Parser(source);
    var parsed=SyntaxEncoder.program(parser.parse());
    var expanded=MacroExpander.syntax(parsed);
    // The Haxe modern parser already emits Int/Ratio/Float literal Syntax:
    // rewriting a second time would visit typed literal leaves incorrectly.
    return inspectResult(boot,boot.invoke('tcCheckSyntax',expanded));
  }

  static function inspectResult(boot:BootRuntime,result:Value):{ok:Bool,types:Array<String>,message:String} {
    var tag=ResultValue.tag(result);
    if(tag==ResultValue.ERR)
      return switch(ResultValue.get(result,ResultValue.ERR)) {
        case Text(message): {ok:false,types:[],message:message};
        case _: throw 'Checker Error must contain Text';
      };
    var checked=ResultValue.get(result,ResultValue.OK);
    var values:Array<String>=[];
    switch(checked) {
      case SyntaxNode('TCChecked',Cons(_, _)) | SyntaxNode('TCChecked',Nil):
        var remaining:Value=switch(checked) {
          case SyntaxNode(_, xs): xs;
          case _: Nil;
        };
        while(true) switch(remaining) {
          case Nil: break;
          case Cons(item,tail):
            var shown=boot.invoke('tcPretty',item);
            switch shown {
              case Text(label): values.push(label);
              case _: throw 'tcPretty must return Text';
            }
            remaining=tail;
          case _: throw 'Checker returned invalid result list';
        }
      case _: throw 'Checker Ok must contain TCChecked';
    }
    return {ok:true,types:values,message:''};
  }

  static function checkGood(boot:BootRuntime,body:String,expected:Array<String>):Void {
    var source='nail 0.54 ; '+body;
    var found=inspect(boot,source);
    eq(found.ok,true,'expected checker success: '+body+' ('+found.message+')');
    eq(found.types,expected,'Nail result types: '+body);
    eq(new TypeChecker().check(source),expected,'Haxe parity: '+body);
  }

  static function checkBad(boot:BootRuntime,body:String,part:String):Void {
    var source='nail 0.54 ; '+body;
    var found=inspect(boot,source);
    eq(found.ok,false,'expected Nail rejection: '+body);
    if(found.message.indexOf(part)<0)
      throw 'NAIL TYPECHECKER: expected diagnostic '+part+', got '+found.message;
    checks++;
    var rejected=false;
    try new TypeChecker().check(source)
    catch(_:Dynamic) rejected=true;
    eq(rejected,true,'Haxe must also reject '+body);
  }

  static function checkMacroGood(boot:BootRuntime,body:String,expected:Array<String>):Void {
    var source='nail 0.54 ; '+body;
    var found=inspectExpanded(boot,source);
    eq(found.ok,true,'expanded Nail macro success: '+body+' ('+found.message+')');
    eq(found.types,expected,'expanded Nail macro types: '+body);
    eq(new TypeChecker().check(source),expected,'Haxe hygienic macro parity: '+body);
  }

  static function checkMacroBad(boot:BootRuntime,body:String,reason:String):Void {
    var source='nail 0.54 ; '+body;
    var found=inspectExpanded(boot,source);
    eq(found.ok,false,'expanded Nail macro must reject: '+body);
    if(found.message.indexOf(reason)<0)
      throw 'NAIL TYPECHECKER: macro expected '+reason+' got '+found.message;
    checks++;
    var rejected=false;
    try new TypeChecker().check(source) catch(_:Dynamic) rejected=true;
    eq(rejected,true,'Haxe must reject expanded macro source: '+body);
  }

  static function checkStructural(boot:BootRuntime,body:String,expected:Array<String>):Void {
    var source='nail 0.54 ; '+body;
    var found=inspect(boot,source);
    eq(found.ok,true,'expected open-row success: '+body+' ('+found.message+')');
    eq(found.types,expected,'Nail open-record type: '+body);
    var parser=new Parser(source,new StringMap<Array<String>>());
    var checker=new TypeChecker();
    eq(checker.checkParsed(parser,parser.parse()),expected,
      'Haxe opt-in open-row parity: '+body);
  }

  static function rejectsStructural(boot:BootRuntime,body:String,reason:String):Void {
    var source='nail 0.54 ; '+body;
    var found=inspect(boot,source);
    eq(found.ok,false,'Nail must reject structural failure: '+body);
    if(found.message.indexOf(reason)<0)
      throw 'NAIL TYPECHECKER: expected '+reason+' got '+found.message;
    checks++;
    var parser=new Parser(source,new StringMap<Array<String>>());
    var checker=new TypeChecker();
    var rejected=false;
    try checker.checkParsed(parser,parser.parse()) catch(_:Dynamic) rejected=true;
    eq(rejected,true,'Haxe must reject same structural failure: '+body);
  }

  static function main():Void {
    var boot=new BootRuntime(60000000);
    var unversioned=boot.invoke('tcCheckSource',Text('1 + 2 ;'));
    eq(ResultValue.tag(unversioned),ResultValue.ERR,
      'legacy numeric source is rejected until dialect-specific checking exists');
    checkGood(boot,'42 ;',['Int']);
    checkGood(boot,'true ;',['Bool']);
    checkGood(boot,'" Ciao " ;',['Text']);
    checkGood(boot,'if true then 1 else 2 ;',['Int']);
    checkGood(boot,'( fun x -> x ) 42 ;',['Int']);
    checkGood(boot,'def id x = x ; id 7 ; id true ;',['Int','Bool']);
    checkGood(boot,'let id = fun x -> x in id " Hello " ;',['Text']);
    checkGood(boot,'def f x = if x then f false else true ; f true ;',['Bool']);
    checkGood(boot,'textConcat " A " " B " ;',['Text']);
    checkGood(boot,'7 + 5 ;',['Int']);
    checkGood(boot,'7 - 5 ;',['Int']);
    checkGood(boot,'7 * 5 ;',['Int']);
    checkGood(boot,'7 / 5 ;',['Ratio']);
    checkGood(boot,'1.25 + 0.5 ;',['Float']);
    checkGood(boot,'1.25 / 0.5 ;',['Float']);
    checkGood(boot,'( 3 / 2 ) + 1 ;',['Ratio']);
    checkBad(boot,'1 + 0.5 ;','No numeric relation instance');
    var inferredNumeric='nail 0.62 ; def add x y = x + y ; add 1 2 ; add 1.5 2.5 ;';
    var numericResult=inspect(boot,inferredNumeric);
    eq(numericResult.ok,true,'0.62 inferred arithmetic constraints');
    eq(numericResult.types,['Int','Float'],'Nail numeric scheme specialization');
    eq(new TypeChecker().check(inferredNumeric),numericResult.types,'Haxe numeric scheme specialization');
    checkGood(boot,'1 == 2 ;',['Bool']);
    checkGood(boot,'" A " != " B " ;',['Bool']);
    checkGood(boot,'[ 1 , 2 ] == [ 1 , 3 ] ;',['Bool']);
    checkGood(boot,'{ x = 1 , y = true } == { x = 2 , y = false } ;',['Bool']);
    checkBad(boot,'1 == true ;','Type mismatch');
    checkBad(boot,'( fun x -> x ) == ( fun y -> y ) ;',
      'Eq constraint');
    checkBad(boot,'[ 1 ] == [ true ] ;','Type mismatch');
    checkGood(boot,
      'def same x y = x == y ; same 3 3 ; same true false ; '
      +'same " A " " B " ;',
      ['Bool','Bool','Bool']);
    checkGood(boot,
      'def same x y = x == y ; '
      +'same [ 1 , 2 ] [ 1 , 3 ] ; '
      +'same [ true ] [ false ] ;',
      ['Bool','Bool']);
    checkGood(boot,
      'def same x y = x == y ; '
      +'let compare = same in [ compare 1 2 , compare " A " " B " ] ;',
      ['[Bool]']);
    checkGood(boot,
      'def same x y = x == y ; def eqList xs ys = same xs ys ; '
      +'eqList [ 1 ] [ 2 ] ; eqList [ true ] [ false ] ;',
      ['Bool','Bool']);
    checkGood(boot,
      'def same x y = x == y ; '
      +'same { x = 1 , y = true } { x = 1 , y = false } ;',
      ['Bool']);
    checkGood(boot,
      'def reflexive x = x == x ; '
      +'reflexive 11 ; reflexive " Echo " ;',
      ['Bool','Bool']);
    checkGood(boot,
      'def makeEq x = fun y -> x == y ; '
      +'makeEq 1 2 ; makeEq " Yes " " No " ;',
      ['Bool','Bool']);
    checkGood(boot,
      'def listEq xs ys = xs == ys ; '
      +'listEq [ { x = 1 } ] [ { x = 2 } ] ;',
      ['Bool']);
    checkBad(boot,
      'def makeEq x = fun y -> x == y ; '
      +'makeEq ( fun x -> x ) ( fun y -> y ) ;',
      'Eq constraint');
    checkBad(boot,
      'def same x y = x == y ; same 1 " Mismatch " ;',
      'Type mismatch');
    checkBad(boot,
      'def same x y = x == y ; '
      +'same ( fun a -> a ) ( fun b -> b ) ;',
      'Eq constraint');
    checkBad(boot,
      'def same x y = x == y ; '
      +'same [ fun x -> x ] [ fun y -> y ] ;',
      'Eq constraint');
    checkGood(boot,'[ 1 , 2 , 3 ] ;',['[Int]']);
    checkGood(boot,'head [ 1 , 2 ] ;',['Int']);
    checkBad(boot,'[ 1 , true ] ;','Type mismatch');

    checkBad(boot,'unknownVar ;','Unknown name');
    checkBad(boot,'1 2 ;','Type mismatch');
    checkBad(boot,'if 1 then true else false ;','Type mismatch');
    checkBad(boot,'if true then 1 else false ;','Type mismatch');
    checkBad(boot,'fun x -> x x ;','Recursive type');

    checkStructural(boot,'( { x = 1 , y = true } ) . x ;',['Int']);
    checkStructural(boot,'def getX r = r . x ; getX { x = 5 , y = true } ;',['Int']);
    checkStructural(boot,'def getX r = r . x ; getX { x = 5 } ;',['Int']);
    checkStructural(boot,
      'def sum r = textConcat ( r . x ) ( r . y ) ; '
      +'sum { x = " Left " , y = " Right " } ;',
      ['Text']);

    // Exchanging two already-known open-row prefixes is type-preserving.
    // The Haxe opt-in checker supplies an independent row-unification oracle.
    checkStructural(boot,
      'def readXY r = textConcat ( r . x ) ( r . y ) ; '
      +'def readYX r = textConcat ( r . y ) ( r . x ) ; '
      +'def readBoth r = textConcat ( readXY r ) ( readYX r ) ; '
      +'readBoth { x = " X " , y = " Y " } ;',
      ['Text']);
    // Two independently inferred requirements have *disjoint* known
    // fields. Their two tails must share one freshly allocated row tail.
    // Use the independent Haxe open-row type checker as a differential oracle.
    checkStructural(boot,
      'def onlyX r = r . x ; def onlyY r = r . y ; '
      +'def join r = [ onlyX r , onlyY r ] ; '
      +'join { x = 7 , y = 9 , extra = true } ;',
      ['[Int]']);
    checkStructural(boot,
      'def firstX r = textConcat ( r . x ) " A " ; '
      +'def firstY r = textConcat ( r . y ) " B " ; '
      +'def join r = textConcat ( firstY r ) ( firstX r ) ; '
      +'join { y = " Y " , x = " X " , extra = 2 } ;',
      ['Text']);
    // Duplicate aliases are invalid even if their field types coincide.
    checkBad(boot,
      'type DoubleField = { x : Text , x : Text } ; '
      +'def take ( r : DoubleField ) = r . x ;',
      'Duplicate structural field');
    // The row-lacks ledger must reject a later tail substitution that
    // repeats an earlier explicitly required field.
    var duplicateRowSource='nail 0.54 ; '
      +'tcUnify '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " tail " ) ) '
      +'( tcRowField " x " ( tcBase " Int " ) '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcStruct [] ) ) ) [] ;';
    var duplicateRowResults=new BootRuntime(60000000).run(duplicateRowSource);
    eq(duplicateRowResults.length,1,'direct duplicate-row probe returns one result');
    eq(ResultValue.tag(duplicateRowResults[0]),ResultValue.ERR,
      'duplicate open-row field must fail the row-lacks guard');
    // Distinct explicit field order with a shared tail is valid.
    var exchangedRows='nail 0.54 ; '
      +'tcUnify '
      +'( tcRowField " x " ( tcBase " Int " ) '
      +'( tcRowField " y " ( tcBase " Text " ) ( tcVar " restA " ) ) ) '
      +'( tcRowField " y " ( tcBase " Text " ) '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " restB " ) ) ) [] ;';
    var exchangedResults=new BootRuntime(60000000).run(exchangedRows);
    eq(exchangedResults.length,1,'direct exchanged-row probe returns one result');
    eq(ResultValue.tag(exchangedResults[0]),ResultValue.OK,
      'row order does not affect explicit-field unification');

    // The crucial row-lacks case: a prefix is initially well-formed and
    // only becomes invalid *after* an independent tail variable is bound.
    var lateDuplicate='nail 0.54 ; '
      +'let guarded = tcUnify '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " openTail " ) ) '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " otherTail " ) ) '
      +'[] in match guarded with '
      +'| Error message -> guarded '
      +'| Ok substitutions -> tcUnify ( tcVar " openTail " ) '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcStruct [] ) ) '
      +'substitutions ;';
    var lateDuplicateValues=new BootRuntime(60000000).run(lateDuplicate);
    eq(lateDuplicateValues.length,1,'late duplicate row returns one result');
    eq(ResultValue.tag(lateDuplicateValues[0]),ResultValue.ERR,
      'row-lacks guard rejects a duplicate introduced after unification');
    // A different field is a legitimate tail extension.
    var lateDistinct='nail 0.54 ; '
      +'let guarded = tcUnify '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " openTail " ) ) '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " otherTail " ) ) '
      +'[] in match guarded with '
      +'| Error message -> guarded '
      +'| Ok substitutions -> tcUnify ( tcVar " openTail " ) '
      +'( tcRowField " y " ( tcBase " Bool " ) ( tcStruct [] ) ) '
      +'substitutions ;';
    var lateDistinctValues=new BootRuntime(60000000).run(lateDistinct);
    eq(lateDistinctValues.length,1,'late distinct row returns one result');
    eq(ResultValue.tag(lateDistinctValues[0]),ResultValue.OK,
      'row-lacks guard allows a distinct tail field');

    // Direct row unification: incomparable prefixes are now permitted
    // with two distinct tails, without changing the VM's runtime types.
    var disjointRows='nail 0.54 ; tcUnify '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " leftTail " ) ) '
      +'( tcRowField " y " ( tcBase " Bool " ) ( tcVar " rightTail " ) ) '
      +'[] ;';
    var rowProbeVm=new BootRuntime(60000000);
    var disjointValues=rowProbeVm.run(disjointRows);
    eq(disjointValues.length,1,'disjoint open rows produce one result');
    eq(ResultValue.tag(disjointValues[0]),ResultValue.OK,
      'disjoint open rows unify through a fresh shared tail');
    var sharedIdentity='nail 0.54 ; '
      +'let unified = tcUnify '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " leftTail " ) ) '
      +'( tcRowField " y " ( tcBase " Bool " ) ( tcVar " rightTail " ) ) '
      +'[] in match unified with '
      +'| Error message -> false '
      +'| Ok substitutions -> '
      +'let left = tcThird ( tcFollow ( tcVar " leftTail " ) substitutions ) in '
      +'let right = tcThird ( tcFollow ( tcVar " rightTail " ) substitutions ) in '
      +'if syntaxTag left == " TCVar " then '
      +'if syntaxTag right == " TCVar " then '
      +'syntaxText left == syntaxText right '
      +'else false else false ;';
    eq(switch(rowProbeVm.run(sharedIdentity)[0]) {
      case Boolean(true): true;
      case _: false;
    },true,'disjoint rows share one identical fresh residual variable');


    // Both residual tails must refer to the same new variable. Binding it
    // to either original field would duplicate a label on one row.
    for (duplicate in [{name:'x',ty:'Int'}, {name:'y',ty:'Bool'}]) {
      var lateSharedDuplicate='nail 0.54 ; '
        +'let unified = tcUnify '
        +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " leftTail " ) ) '
        +'( tcRowField " y " ( tcBase " Bool " ) ( tcVar " rightTail " ) ) '
        +'[] in match unified with '
        +'| Error message -> unified '
        +'| Ok substitutions -> '
        +'let residual = tcFollow ( tcVar " leftTail " ) substitutions in '
        +'let shared = tcThird residual in '
        +'tcUnify shared '
        +'( tcRowField " '+duplicate.name+' " '
        +'( tcBase " '+duplicate.ty+' " ) '
        +'( tcStruct [] ) ) substitutions ;';
      var duplicateValues=rowProbeVm.run(lateSharedDuplicate);
      eq(ResultValue.tag(duplicateValues[0]),ResultValue.ERR,
        'shared tail cannot duplicate prior field: '+duplicate.name);
    }
    var lateSharedDistinct='nail 0.54 ; '
      +'let unified = tcUnify '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " leftTail " ) ) '
      +'( tcRowField " y " ( tcBase " Bool " ) ( tcVar " rightTail " ) ) '
      +'[] in match unified with '
      +'| Error message -> unified '
      +'| Ok substitutions -> '
      +'let residual = tcFollow ( tcVar " leftTail " ) substitutions in '
      +'let shared = tcThird residual in '
      +'tcUnify shared ( tcRowField " z " ( tcBase " Text " ) '
      +'( tcStruct [] ) ) substitutions ;';
    var distinctValues=rowProbeVm.run(lateSharedDistinct);
    eq(ResultValue.tag(distinctValues[0]),ResultValue.OK,
      'shared tail accepts a genuinely new field');

    // Identical tail variables cannot absorb mutually exclusive fields.
    var sameTail='nail 0.54 ; tcUnify '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " sameTail " ) ) '
      +'( tcRowField " y " ( tcBase " Bool " ) ( tcVar " sameTail " ) ) '
      +'[] ;';
    eq(ResultValue.tag(rowProbeVm.run(sameTail)[0]),ResultValue.ERR,
      'one tail cannot make conflicting row prefixes equal');

    var incompatibleCommon='nail 0.54 ; tcUnify '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " leftTail " ) ) '
      +'( tcRowField " x " ( tcBase " Bool " ) ( tcVar " rightTail " ) ) '
      +'[] ;';
    eq(ResultValue.tag(rowProbeVm.run(incompatibleCommon)[0]),ResultValue.ERR,
      'shared structural labels must agree on their types');

    // Even a projection that immediately finds the first field must store
    // a row-lacks guard: open-row schemes can be instantiated without a
    // pre-existing substitution entry for that structural prefix.
    var projectedDuplicate='nail 0.54 ; '
      +'let projected = tcProjectField '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " freeTail " ) ) '
      +'" x " [] [] " seed " in '
      +'tcUnify ( tcVar " freeTail " ) '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcStruct [] ) ) '
      +'( tcResultSubs projected ) ;';
    eq(ResultValue.tag(rowProbeVm.run(projectedDuplicate)[0]),ResultValue.ERR,
      'projecting the first field retains the late duplicate-label guard');
    var projectedDistinct='nail 0.54 ; '
      +'let projected = tcProjectField '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " freeTail " ) ) '
      +'" x " [] [] " seed " in '
      +'tcUnify ( tcVar " freeTail " ) '
      +'( tcRowField " z " ( tcBase " Bool " ) ( tcStruct [] ) ) '
      +'( tcResultSubs projected ) ;';
    eq(ResultValue.tag(rowProbeVm.run(projectedDistinct)[0]),ResultValue.OK,
      'projected row still accepts a distinct late tail field');

    // Generalization must retain a negative field requirement on a
    // quantified row tail, even if no open-row substitution is active when
    // the function is later instantiated.
    var genericRowScheme='nail 0.54 ; '
      +'let scheme = tcGeneralize '
      +'( tcFun '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcVar " polyTail " ) ) '
      +'( tcBase " Int " ) ) [] [] in ';
    eq(switch(rowProbeVm.run(genericRowScheme
      +'isEmpty ( tcSchemeRowGuards scheme ) ;')[0]) {
      case Boolean(false): true;
      case _: false;
    },true,'generalized row scheme stores a negative field qualifier');

    var duplicatedInstantiatedTail=genericRowScheme
      +'let instantiated = tcInstantiate scheme [] " inst " in '
      +'let domain = tcFirst ( tcResultType instantiated ) in '
      +'tcUnify ( tcThird domain ) '
      +'( tcRowField " x " ( tcBase " Int " ) ( tcStruct [] ) ) '
      +'( tcResultSubs instantiated ) ;';
    eq(ResultValue.tag(rowProbeVm.run(duplicatedInstantiatedTail)[0]),
      ResultValue.ERR,
      'instantiating a row scheme restores the x-lacks constraint');

    var validInstantiatedTail=genericRowScheme
      +'let instantiated = tcInstantiate scheme [] " inst " in '
      +'let domain = tcFirst ( tcResultType instantiated ) in '
      +'tcUnify ( tcThird domain ) '
      +'( tcRowField " z " ( tcBase " Bool " ) ( tcStruct [] ) ) '
      +'( tcResultSubs instantiated ) ;';
    eq(ResultValue.tag(rowProbeVm.run(validInstantiatedTail)[0]),
      ResultValue.OK,
      'instantiated row tail accepts a nonconflicting extra field');

    // A constraint may be in the immutable substitution ledger without
    // appearing in the generalized type's surface shape. The scheme must
    // still carry it if its tail variable is quantified.
    var storedOnlyScheme='nail 0.54 ; '
      +'let original = tcRememberRow '
      +'( tcRowField " reserved " ( tcBase " Text " ) '
      +'( tcVar " onlyTail " ) ) [] in '
      +'match original with '
      +'| Error message -> original '
      +'| Ok originalSubs -> '
      +'let scheme = tcGeneralize ( tcVar " onlyTail " ) [] originalSubs in '
      +'let instantiated = tcInstantiate scheme [] " new " in '
      +'tcUnify ( tcResultType instantiated ) '
      +'( tcRowField " reserved " ( tcBase " Text " ) '
      +'( tcStruct [] ) ) ( tcResultSubs instantiated ) ;';
    eq(ResultValue.tag(rowProbeVm.run(storedOnlyScheme)[0]),ResultValue.ERR,
      'generalization preserves row guards stored outside the type shape');

    // A tail tied to an enclosing lexical environment is NOT quantified:
    // its existing guard belongs to that environment, not a polymorphic
    // copy. Otherwise callers could observe invented constraints.
    var fixedTailScheme='nail 0.54 ; '
      +'let recorded = tcRememberRow '
      +'( tcRowField " x " ( tcBase " Int " ) '
      +'( tcVar " fixedTail " ) ) [] in '
      +'match recorded with '
      +'| Error message -> false '
      +'| Ok substitutions -> '
      +'let environment = [ tcBinding " outer " '
      +'( tcScheme ( tcVar " fixedTail " ) [] ) ] in '
      +'let scheme = tcGeneralize ( tcVar " fixedTail " ) '
      +'environment substitutions in '
      +'isEmpty ( tcSchemeRowGuards scheme ) ;';
    eq(switch(rowProbeVm.run(fixedTailScheme)[0]) {
      case Boolean(true): true;
      case _: false;
    },true,'an environment-fixed tail must not acquire quantified guards');

    // Row qualifiers nested in a type constructor must also be captured.
    var nestedScheme='nail 0.54 ; '
      +'let scheme = tcGeneralize '
      +'( tcList ( tcRowField " item " ( tcBase " Bool " ) '
      +'( tcVar " listTail " ) ) ) [] [] in '
      +'isEmpty ( tcSchemeRowGuards scheme ) ;';
    eq(switch(rowProbeVm.run(nestedScheme)[0]) {
      case Boolean(false): true;
      case _: false;
    },true,'quantified open-row guard survives inside a list element');


    // Different calls to a polymorphic accessor receive independent
    // instantiations; Haxe's opt-in structural checker is the oracle.
    checkStructural(boot,
      'def readX r = r . x ; '
      +'readX { x = 17 , y = true } ; '
      +'readX { x = " another " , z = false } ;',
      ['Int','Text']);





    rejectsStructural(boot,'def getX r = r . x ; getX { y = true } ;',
      'Missing structural field');
    rejectsStructural(boot,
      'def getX r = textConcat ( r . x ) " S " ; '
      +'getX { x = true } ;',
      'Type mismatch');
    var person='type Person { name Text age Int } ; ';
    var box='type Box a { value a } ; ';
    var pair='type Pair a b { first a second b } ; ';
    checkGood(boot,person+'( Person " Ada " 36 ) . name ;',['Text']);
    checkGood(boot,person+'( Person { age = 36 , name = " Ada " } ) . age ;',
      ['Int']);
    checkGood(boot,person+'def read p = p . name ; read ( Person " C " 12 ) ;',
      ['Text']);
    checkGood(boot,box+'( Box true ) . value ; ( Box 7 ) . value ;',
      ['Bool','Int']);
    checkGood(boot,box+'def wrap x = Box x ; '
      +'( wrap 42 ) . value ; ( wrap false ) . value ;',
      ['Int','Bool']);
    checkGood(boot,pair+'( Pair 9 true ) . first ; '
      +'( Pair " Y " 6 ) . second ;',['Int','Int']);
    checkGood(boot,person+'type Badge { owner Person valid Bool } ; '
      +'( Badge { valid = true , owner = Person " Jo " 9 } ) . owner . age ;',
      ['Int']);
    checkGood(boot,box+'Box 1 == Box 2 ;',['Bool']);
    checkBad(boot,person+'Person true 1 ;','Type mismatch');
    checkBad(boot,person+'Person { name = " Ada " } ;',
      'Nominal record field count mismatch');
    checkBad(boot,person+'Person { name = " Ada " , invalid = 2 } ;',
      'Missing named record field');
    checkBad(boot,box+'Box ( fun x -> x ) == Box ( fun y -> y ) ;',
      'Eq constraint');
    checkBad(boot,'type A { value Int } ; type B { value Int } ; '
      +'if true then A 1 else B 2 ;','Type mismatch');
    checkBad(boot,'type Person { name Text } ; '
      +'type Company { name Text } ; '
      +'def get x = x . name ;',
      'Ambiguous nominal record field');
    checkBad(boot,'type Box a { value a } ; '
      +'type Holder { inner Box } ;',
      'Parameterized nominal field');
    checkBad(boot,'type Plain { value Int } ; '
      +'( Plain true ) . value ;','Type mismatch');

    var option='type Option a = None | Some a ; ';
    checkGood(boot,'type Color = Red | Blue ; Red ; Blue ;',
      ['Color','Color']);
    checkGood(boot,'type Color = Red | Blue ; '
      +'if true then Red else Blue ;',['Color']);
    checkGood(boot,option+'Some 42 ; Some true ;',
      ['Option[Int]','Option[Bool]']);
    checkGood(boot,option+'Some 3 == Some 4 ;',['Bool']);
    checkGood(boot,'type Tree = Leaf Int | Branch Tree Tree ; '
      +'Branch ( Leaf 1 ) ( Leaf 2 ) ;',['Tree']);
    checkGood(boot,'type Reply a e = Success a | Failure e ; '
      +'def result x = if true then Success x else Failure " Fail " ; '
      +'result 4 ;',['Reply[Int, Text]']);
    checkBad(boot,option+'Some 4 true ;','Type mismatch');
    checkBad(boot,option+'Some true == Some 3 ;','Type mismatch');
    checkBad(boot,'type First = A | B ; type Second = C | D ; '
      +'if true then A else C ;','Type mismatch');
    checkBad(boot,option+'type Other a = Some a ;',
      'Duplicate sum constructor');

    // Lowered list patterns retain ordinary HM types; generated helpers are
    // typed by Nail, not delegated to the Haxe reference checker.
    checkGood(boot,'def firstOr fallback = function '
      +'| [] -> fallback | item :: rest -> item ; '
      +'firstOr 3 [ 4 , 5 ] ; firstOr 3 [] ;',['Int','Int']);
    checkGood(boot,'match [ 9 , 8 ] with '
      +'| [] -> 0 | first :: rest -> first ;',['Int']);
    checkBad(boot,'def broken = function '
      +'| [] -> 0 | first :: rest -> true ;',
      'Type mismatch');

    // Nominal patterns: coverage, binding arity and constructor ownership
    // are checked before the private #sumFail fallback is inferred.
    checkGood(boot,'type Color = Red | Blue ; '
      +'match Red with | Red -> 1 | Blue -> 2 ;',['Int']);
    checkGood(boot,option+'def unwrap = function '
      +'| None -> 0 | Some value -> value ; '
      +'unwrap ( Some 42 ) ;',['Int']);
    checkGood(boot,'type Status = Rest | Played Int ; '
      +'def tempo = function | Rest -> 0 | Played bpm -> bpm ; '
      +'tempo ( Played 116 ) ;',['Int']);
    checkGood(boot,option+'def classify = function '
      +'| None -> false | Some xs -> '
      +'( function | [] -> false | first :: rest -> true ) xs ; '
      +'classify ( Some [ 3 ] ) ;',['Bool']);
    checkBad(boot,option+'def partial = function '
      +'| Some value -> true ;','Non-exhaustive match');
    checkBad(boot,option+'def wrongArity = function '
      +'| None -> false | Some -> true ;',
      'Constructor match binding arity mismatch');
    checkBad(boot,'type First = One ; type Second = Two ; '
      +'def mixed = function | One -> 1 | Two -> 2 ;',
      'Mixed constructors');
    checkBad(boot,option+'def unknown = function '
      +'| None -> 0 | NotDeclared x -> x ;',
      'Unknown algebraic constructor');

    // Hygienic macro expansion adds private #macro_local_ subject binders
    // and #macro_global_ references to predicates, accessors and helpers.
    // The Nail type checker must preserve the original global binding.
    checkMacroGood(boot,option
      +'macro unwrap p = quote ( match unquote p with '
      +'| None -> 0 | Some value -> value ) ; '
      +'expand unwrap ( Some 42 ) ;',['Int']);
    checkMacroGood(boot,'type Color = Red | Blue ; '
      +'macro color x = quote ( match unquote x with '
      +'| Red -> " R " | Blue -> " B " ) ; '
      +'expand color Blue ;',['Text']);
    checkMacroGood(boot,option
      +'macro makeUnwrapper = quote ( function '
      +'| None -> 0 | Some item -> item ) ; '
      +'def unwrap = expand makeUnwrapper ; unwrap ( Some 21 ) ;',['Int']);
    checkMacroGood(boot,'def helper x = x ; '
      +'macro applyHelper arg = quote ( helper ( unquote arg ) ) ; '
      +'let helper = fun x -> true in expand applyHelper 42 ;',['Int']);
    checkMacroBad(boot,option
      +'macro missingCase x = quote ( match unquote x with '
      +'| Some item -> item ) ; '
      +'expand missingCase ( Some 1 ) ;','Non-exhaustive match');
    checkMacroBad(boot,'type One = Only ; type Two = Other ; '
      +'macro mixed x = quote ( match unquote x with '
      +'| Only -> 1 | Other -> 2 ) ; '
      +'expand mixed Only ;','Mixed constructors');

    // Full Nail source path: preserve static type metadata while expanding
    // macros before HM inference, without Haxe-side AST preparation.
    checkGood(boot,option
      +'macro unwrap p = quote ( match unquote p with '
      +'| None -> 0 | Some value -> value ) ; '
      +'expand unwrap ( Some 42 ) ;',['Int']);
    checkGood(boot,'def helper x = x ; '
      +'macro applyHelper arg = quote ( helper ( unquote arg ) ) ; '
      +'let helper = fun x -> true in expand applyHelper 42 ;',['Int']);
    checkGood(boot,'type Box a { value a } ; '
      +'macro makeBox x = quote ( Box ( unquote x ) ) ; '
      +'( expand makeBox 7 ) . value ;',['Int']);
    checkStructural(boot,'def id ( x : Int ) = x ; '
      +'macro callId x = quote ( id ( unquote x ) ) ; '
      +'expand callId 42 ;',['Int']);
    checkGood(boot,'Add : Int Int Int ; '
      +'macro sumInt x = quote ( unquote x + 1 ) ; '
      +'expand sumInt 9 ;',['Int']);
    checkBad(boot,option
      +'macro partial p = quote ( match unquote p with '
      +'| Some x -> x ) ; expand partial ( Some 1 ) ;',
      'Non-exhaustive match');
    checkBad(boot,'macro broken x = quote ( unquote missing ) ; '
      +'expand broken 1 ;','unknown unquote parameter');

    var htmlContract='type Html = { h2 : Text Text , div : Text Text } ; ';
    checkStructural(boot,htmlContract
      +'def html = { h2 = fun x -> textConcat " H: " x , '
      +'div = fun x -> x } ; '
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'render html " Test " ;',['Text']);
    checkStructural(boot,htmlContract
      +'def render ( html : Html ) ( title : Text ) = html { h2 title } ; '
      +'render { h2 = fun x -> x , div = fun x -> x , extra = true } '
      +'" Typed " ;',['Text']);
    checkStructural(boot,htmlContract
      +'def html : Html = { h2 = fun x -> x , div = fun x -> x } ; '
      +'html . h2 " Value " ;',['Text']);
    rejectsStructural(boot,htmlContract
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'render { h2 = fun x -> x } " Missing " ;',
      'Missing structural field');
    rejectsStructural(boot,htmlContract
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'render { h2 = fun x -> true , div = fun x -> x } " Wrong " ;',
      'Type mismatch');
    rejectsStructural(boot,'type Html = { h2 : UnknownType Text } ; '
      +'def render ( html : Html ) = html { h2 " X " } ;',
      'Unknown type');

    // Correctness gate for PR #28: compare lexical contextual resolution in
    // the self-hosted HM checker with the independent Haxe type checker.
    // An inner context's div must shadow the outer div even when that makes
    // the program ill-typed; explicit html . div must still select the outer.
    var nestedContracts='type Html = { h2 : Text Text , div : Text Text } ; '
      +'type Math = { div : Bool Text } ; ';
    var nestedValues='def htmlValue = { h2 = fun x -> x , '
      +'div = fun x -> textConcat " outer: " x } ; '
      +'def mathValue = { div = fun x -> if x then " yes " else " no " } ; ';
    checkStructural(boot,nestedContracts+nestedValues
      +'def render ( html : Html ) ( math : Math ) = '
      +'html { h2 ( math { html . div " X " } ) } ; '
      +'render htmlValue mathValue ;',['Text']);
    rejectsStructural(boot,nestedContracts+nestedValues
      +'def render ( html : Html ) ( math : Math ) = '
      +'html { h2 ( math { div " Wrong " } ) } ; '
      +'render htmlValue mathValue ;','Type mismatch');
    checkStructural(boot,nestedContracts+nestedValues
      +'def render ( html : Html ) ( math : Math ) = '
      +'html { h2 ( math { div true } ) } ; '
      +'render htmlValue mathValue ;',['Text']);
    checkStructural(boot,htmlContract
      +'def htmlValue = { h2 = fun x -> x , div = fun x -> x } ; '
      +'def render ( html : Html ) = html { '
      +'let h2 = fun x -> textConcat " local: " x in h2 " X " } ; '
      +'render htmlValue ;',['Text']);
    rejectsStructural(boot,htmlContract
      +'def html : Html = { h2 = fun x -> x } ; '
      +'html . h2 " X " ;','Missing structural field');
    rejectsStructural(boot,htmlContract
      +'def html : Html = { h2 = fun x -> true , div = fun x -> x } ; '
      +'html . h2 " X " ;','Type mismatch');

    // Check actual nested context execution, not just the inferred type.
    // An unqualified name must resolve to the innermost field, while a
    // qualified outer reference keeps its original receiver.
    var nestedRuntimeSource='nail 0.54 ; '
      +'type OuterRuntime = { div : Text Text } ; '
      +'type InnerRuntime = { div : Bool Text } ; '
      +'def outerRuntime = { div = fun x -> " outer " } ; '
      +'def innerRuntime = { div = fun x -> '
      +'if x then " inner " else " other " } ; '
      +'def runInner ( outer : OuterRuntime ) ( inner : InnerRuntime ) = '
      +'outer { inner { div true } } ; '
      +'def runOuter ( outer : OuterRuntime ) ( inner : InnerRuntime ) = '
      +'outer { inner { outer . div " X " } } ; '
      +'runInner outerRuntime innerRuntime ; '
      +'runOuter outerRuntime innerRuntime ;';
    var nestedChecked=nail.RuntimeValues.plainResults(
      new BootRuntime().runTypecheckedExperimental(nestedRuntimeSource));
    eq(nestedChecked,['inner','outer'],
      'nested checked execution respects inner shadowing and explicit outer access');
    eq(nestedChecked,nail.RuntimeValues.plainResults(
      new BootRuntime().run(nestedRuntimeSource)),
      'checked and ordinary execution agree on nested contextual lookup');

    // The source-free compiler erases annotations when compiling. The new
    // opt-in checked execution path must validate in Nail *before* running.
    var checkedContext='nail 0.54 ; '+htmlContract
      +'def html = { h2 = fun x -> x , div = fun x -> x } ; '
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'render html " Verified " ;';
    eq(nail.RuntimeValues.plainResults(
      boot.runTypecheckedExperimental(checkedContext)),['Verified'],
      'opt-in checked execution accepts a valid annotated context');
    eq([for (name in boot.names())
      if (StringTools.startsWith(name,'#tc_static_form_')) name].length,0,
      'checked runtime must not install compiler-only static declarations');

    // The checker must authorize the exact executable Syntax submitted to
    // the bytecode compiler. Differential bytecode/behavior comparisons
    // catch parser, macro-expander, numeric and contextual-lowering drift.
    for (checkedSource in [
      'nail 0.54 ; 1 + 2 ;',
      'nail 0.54 ; if true then " Yes " else " No " ;',
      'nail 0.54 ; macro id x = quote ( unquote x ) ; '
        +'expand id 42 ;',
      'nail 0.54 ; macro add x = quote ( unquote x + 1 ) ; '
        +'expand add 41 ;',
      'nail 0.54 ; macro literal = quote ( 1.5 ) ; '
        +'expand literal ;',
      checkedContext
    ]) {
      var ordinaryBytecode=boot.compile(checkedSource);
      var checkedBytecode=boot.compileTypecheckedExperimental(checkedSource);
      eq(normalizedMacro(checkedBytecode,new StringMap<String>(),0),
        normalizedMacro(ordinaryBytecode,new StringMap<String>(),0),
        'checked and regular compilers agree on bytecode: '+checkedSource);
      // The annotated fixture already ran above, and re-running a top-level
      // definition in one VM should correctly be rejected as a duplicate.
      // Its bytecode is compared above; expression-only cases run both ways.
      if (checkedSource != checkedContext)
        eq(nail.RuntimeValues.plainResults(boot.runBytecode(checkedBytecode)),
          nail.RuntimeValues.plainResults(boot.runBytecode(ordinaryBytecode)),
          'checked and regular bytecode execute equally: '+checkedSource);
    }

    // Executable parity corpus: approved source must produce the same
    // bytecode and observable results as the ordinary compiler. Reusing two
    // independent runtimes also catches checker-only globals leaking into
    // later programs without hiding genuine duplicate-definition errors.
    // Match the existing HM suite's bounded VM execution guard.
    var checkedParityVm=new BootRuntime(60000000);
    var ordinaryParityVm=new BootRuntime(60000000);
    for (paritySource in [
      // Nominal generic construction and projection.
      'nail 0.54 ; type ParityBox a { value a } ; '
        +'( ParityBox 23 ) . value ;',
      // Exhaustive sum-pattern lowering and its private fallback.
      'nail 0.54 ; type ParityOption a = ParityNone | ParitySome a ; '
        +'match ( ParitySome 12 ) with '
        +'| ParityNone -> 0 | ParitySome value -> value ;',
      // Compile-time-only numerical relation rows must not appear as
      // executable user definitions, even when several rows exist.
      'nail 0.54 ; ParityAdd : Int Int Int ; '
        +'ParityAdd : Float Float Float ; '
        +'def parityAdd x y : ParityAdd = x + y ; '
        +'parityAdd 3 4 ; parityAdd 1.25 0.5 ;',
      // An Eq-qualified polymorphic function used at distinct types.
      'nail 0.54 ; def paritySame x y = x == y ; '
        +'paritySame [ 1 , 2 ] [ 1 , 2 ] ; '
        +'paritySame " A " " B " ;',
      // The compiler must execute the exact macro-expanded sum pattern
      // that passed the Nail checker, with no second expansion.
      'nail 0.54 ; type ParityColor = ParityRed | ParityBlue ; '
        +'macro parityName x = quote ( match unquote x with '
        +'| ParityRed -> " red " | ParityBlue -> " blue " ) ; '
        +'expand parityName ParityBlue ;'
    ]) {
      var checkedProgram=checkedParityVm.compileTypecheckedExperimental(paritySource);
      var ordinaryProgram=ordinaryParityVm.compile(paritySource);
      eq(normalizedMacro(checkedProgram,new StringMap<String>(),0),
        normalizedMacro(ordinaryProgram,new StringMap<String>(),0),
        'checked/ordinary bytecode parity across type features: '+paritySource);
      var checkedValues=nail.RuntimeValues.plainResults(
        checkedParityVm.runBytecode(checkedProgram));
      eq(checkedValues,nail.RuntimeValues.plainResults(
        ordinaryParityVm.runBytecode(ordinaryProgram)),
        'checked/ordinary runtime parity across type features: '+paritySource);
      eq([for (name in checkedParityVm.names())
        if (StringTools.startsWith(name,'#tc_static_form_')) name].length,0,
        'static type metadata never leaks into VM global bindings');
    }

    for (rejected in [
      {source:'nail 0.54 ; '+htmlContract
        +'def html : Html = { h2 = fun x -> x } ; '
        +'html . h2 " X " ;',reason:'Missing structural field'},
      {source:'nail 0.54 ; '+htmlContract
        +'def html : Html = { h2 = fun x -> true , div = fun x -> x } ; '
        +'html . h2 " X " ;',reason:'Type mismatch'},
      {source:'nail 0.54 ; 1 + 1.0 ;',
        reason:'No numeric relation instance'},
      {source:'1 ;',reason:'requires versioned modern source'}
    ]) {
      var namesBefore=boot.names();
      var checkError='';
      try boot.runTypecheckedExperimental(rejected.source)
      catch(e:Dynamic) checkError=Std.string(e);
      eq(checkError.indexOf(rejected.reason)>=0,true,
        'checked execution fails closed before runtime: '+rejected.reason);
      // Compare the whole binding set, not just its size: a checker
      // rejection must neither add nor replace an existing VM global.
      namesBefore.sort(Reflect.compare);
      var namesAfter=boot.names();
      namesAfter.sort(Reflect.compare);
      eq(namesAfter,namesBefore,
        'rejected checked source cannot change VM globals: '
          +rejected.reason);
      eq(nail.RuntimeValues.plainResults(
        boot.runTypecheckedExperimental('nail 0.54 ; " recovered " ;')),
        ['recovered'],
        'VM remains usable after rejected checked source: '+rejected.reason);
    }
    // Rejection must be atomic with respect to program execution. A
    // successfully typed definition preceding the fault is *not* executed.
    var forbiddenName='neverBoundByRejectedTypecheck';
    eq(boot.names().indexOf(forbiddenName),-1,
      'checked gate fixture begins without forbidden global');
    var partialSource='nail 0.54 ; '+htmlContract
      +'def '+forbiddenName+' = 42 ; '
      +'def html : Html = { h2 = fun x -> x } ; '
      +'html . h2 " X " ;';
    var partialError='';
    try boot.runTypecheckedExperimental(partialSource)
    catch(e:Dynamic) partialError=Std.string(e);
    eq(partialError.indexOf('Missing structural field')>=0,true,
      'checked execution rejects invalid later definition');
    eq(boot.names().indexOf(forbiddenName),-1,
      'checked execution must not commit an earlier valid definition');

    // A type-check failure from any lowering must reject the *entire*
    // application before its earlier valid top-level definitions execute.
    // Exercise distinct fail-closed paths, not only structural annotations.
    for (rejection in [
      {name:'neverBoundBadNumeric',tail:'1 + 1.0 ;',
        reason:'No numeric relation instance'},
      {name:'neverBoundBadPattern',
        tail:'type GuardChoice = GuardFirst | GuardSecond ; '
          +'match GuardFirst with | GuardFirst -> 1 ;',
        reason:'Non-exhaustive match'},
      {name:'neverBoundBadMacro',
        tail:'macro guardBad x = quote ( unquote missing ) ; '
          +'expand guardBad 1 ;',
        reason:'unknown unquote parameter'}
    ]) {
      var beforeGlobals=boot.names();
      var rejectedSource='nail 0.54 ; def '+rejection.name
        +' = " unexpectedly executed " ; '+rejection.tail;
      var rejectionError='';
      try boot.runTypecheckedExperimental(rejectedSource)
      catch (error:Dynamic) rejectionError=Std.string(error);
      eq(rejectionError.indexOf(rejection.reason)>=0,true,
        'fail-closed checked execution: '+rejection.reason);
      var afterGlobals=boot.names();
      beforeGlobals.sort(Reflect.compare);
      afterGlobals.sort(Reflect.compare);
      eq(afterGlobals,beforeGlobals,
        'no application definition committed for '+rejection.reason);
      eq(boot.names().indexOf(rejection.name),-1,
        'invalid checked source did not execute its first definition');
    }
    // A preceding failure must not poison a subsequent valid submission.
    eq(boot.names().indexOf('checkedRecoveryValue'),-1,
      'recovery test begins with no binding');
    eq(nail.RuntimeValues.plainResults(
      boot.runTypecheckedExperimental('nail 0.54 ; '
        +'def checkedRecoveryValue = " recovered " ; '
        +'checkedRecoveryValue ;')),
      ['recovered'],'checked VM can commit a later valid definition');

    checkGood(boot,'Add : Int Int Int ; Add : Float Float Float ; '
      +'def add x y : Add = x + y ; add 6 7 ; add 1.25 0.5 ;',
      ['Int','Float']);
    checkGood(boot,'Div : Int Int Ratio ; Div : Float Float Float ; '
      +'def divide x y : Div = x / y ; divide 7 2 ; divide 7.0 2.0 ;',
      ['Ratio','Float']);
    checkGood(boot,'Merge : Text Text Text ; '
      +'def merge a b : Merge = textConcat a b ; '
      +'merge " A " " B " ;',['Text']);
    checkBad(boot,'Add : Int Int Ratio ; '
      +'def wrong a b : Add = a + b ;','Type mismatch');
    checkBad(boot,'Add : Int Int Int ; Add : Int Int Int ; '
      +'def add x y : Add = x + y ;',
      'Duplicate relation input types');
    checkBad(boot,'Add : Int Int Int ; '
      +'def add x y : Add = x + y ; add 1.0 2.0 ;',
      'No relation instance');
    checkGood(boot,
      'Join3 : Text Text Text Text ; '
      +'def join3 a b c : Join3 = textConcat ( textConcat a b ) c ; '
      +'join3 " A " " B " " C " ;',['Text']);
    checkGood(boot,
      'Pick : Text Int Bool Text ; Pick : Bool Text Int Bool ; '
      +'def pick x y z : Pick = x ; '
      +'pick " A " 5 true ; pick false " B " 6 ;',
      ['Text','Bool']);
    checkGood(boot,
      'Len : Text Int ; '
      +'def len x : Len = textLengthInt x ; '
      +'len " Hello " ;',['Int']);
    checkGood(boot,
      'Join4 : Text Text Text Text Text ; '
      +'def join4 a b c d : Join4 = '
      +'textConcat ( textConcat a b ) ( textConcat c d ) ; '
      +'join4 " A " " B " " C " " D " ;',['Text']);
    checkBad(boot,
      'Pick : Text Int Bool Text ; Pick : Text Int Bool Bool ; '
      +'def pick x y z : Pick = x ;',
      'Duplicate relation input types');
    checkBad(boot,
      'Pick : Text Int Bool Text ; Pick : Text Int Text ; '
      +'def pick x y z : Pick = x ;',
      'Inconsistent relation arity');
    checkBad(boot,
      'Join3 : Text Text Text Text ; '
      +'def join3 a b : Join3 = textConcat a b ;',
      'Relation definition arity');
    checkBad(boot,
      'Join3 : Text Text Text Text ; '
      +'def join3 a b c d : Join3 = textConcat a b ;',
      'Relation definition arity');
    checkBad(boot,
      'Pick : Text Int Bool Text ; '
      +'def pick x y z : Pick = x ; '
      +'pick " A " true 5 ;',
      'No relation instance');
    var params=[for(i in 1...17) 'p'+i];
    var signature=[for(i in 0...17) 'Text'].join(' ');
    var values=[for(i in 0...16) '" T "'].join(' ');
    checkGood(boot,
      'Wide : '+signature+' ; '
      +'def wide '+params.join(' ')+' : Wide = p1 ; '
      +'wide '+values+' ;',['Text']);
    // The diagnostic adapter must use Nail's checker result, never run the
    // host TypeChecker or a second parser to invent source coordinates.
    var report=NailSourceAnalysis.analyze(
      'nail 0.54 ; def id x = x ; id 7 ;',boot);
    eq(report.ok,true,'Nail source report succeeds');
    eq(report.types,['Int'],'Nail report retains inferred evaluations');
    eq(report.diagnostics.length,0,'success has no diagnostics');

    var missingSource='nail 0.54 ;\ndef broken = missing ;';
    report=NailSourceAnalysis.analyze(missingSource,boot);
    eq(report.ok,false,'Nail report rejects unknown identifier');
    eq(report.diagnostics[0].phase,'type','Nail diagnostic phase');
    eq(report.diagnostics[0].span != null,true,
      'unique unknown identifier receives original location: '
        +Json.stringify(report));
    eq(report.diagnostics[0].span.start,missingSource.indexOf('missing'),
      'unknown identifier original UTF-16 offset');
    eq(report.diagnostics[0].span.line,2,'unknown identifier line');
    eq(report.diagnostics[0].span.column,14,'unknown identifier column');

    var commented='nail 0.54 ; # missing in a comment\n'
      +'def broken = missing ; " missing " ;';
    report=NailSourceAnalysis.analyze(commented,boot);
    eq(report.diagnostics[0].span != null,true,
      'quoted text and comments are excluded from matching');
    eq(report.diagnostics[0].span.start,commented.indexOf('missing ;'),
      'unknown identifier excludes comment/quoted occurrences');

    var repeated='nail 0.54 ; def bad = missing ; def later = missing ;';
    report=NailSourceAnalysis.analyze(repeated,boot);
    eq(report.diagnostics[0].span != null,true,
      'Nail fault trail disambiguates repeated identifiers across forms');
    eq(report.diagnostics[0].span.start,repeated.indexOf('missing'),
      'error resolves to first failing declaration, not the later occurrence');

    var repeatedInOne='nail 0.54 ; def bad = if true then missing else missing ;';
    report=NailSourceAnalysis.analyze(repeatedInOne,boot);
    eq(report.diagnostics[0].span != null,true,
      'Nail expression path disambiguates repeated identifiers in one form');
    eq(report.diagnostics[0].span.start,repeatedInOne.indexOf('missing'),
      'then-branch is visited before else-branch');

    var numericOperands='nail 0.54 ; def bad = missing + missing ;';
    report=NailSourceAnalysis.analyze(numericOperands,boot);
    eq(report.diagnostics[0].span.start,numericOperands.indexOf('missing'),
      'numeric overload traces the first operand of a lowered call');

    var equalityOperands='nail 0.54 ; def bad = missing == missing ;';
    report=NailSourceAnalysis.analyze(equalityOperands,boot);
    eq(report.diagnostics[0].span.start,equalityOperands.indexOf('missing'),
      'equality traces the first operand of a lowered call');

    var failingElse='nail 0.54 ; def bad = if true then 1 else missing ;';
    report=NailSourceAnalysis.analyze(failingElse,boot);
    eq(report.diagnostics[0].span.start,failingElse.indexOf('missing'),
      'Nail expression path resolves If else child');

    var nested='nail 0.54 ; def bad x = if x then x else missing ;';
    report=NailSourceAnalysis.analyze(nested,boot);
    eq(report.diagnostics[0].span.start,nested.indexOf('missing'),
      'Nail expression path traverses lambda and conditional');

    var applied='nail 0.54 ; def id x = x ; def bad = id missing ;';
    report=NailSourceAnalysis.analyze(applied,boot);
    eq(report.diagnostics[0].span.start,applied.indexOf('missing'),
      'Nail expression path traverses application argument');

    var duplicated='nail 0.54 ; def twice x = x ; def twice y = y ;';
    report=NailSourceAnalysis.analyze(duplicated,boot);
    eq(report.ok,false,'duplicate definition is rejected');
    eq(report.diagnostics[0].span.start,duplicated.lastIndexOf('twice'),
      'second declaration is the failing source location');

    report=NailSourceAnalysis.analyze(
      'nail 0.54 ; def wrong = 1 + true ;',boot);
    eq(report.ok,false,'numeric mismatch is rejected');
    eq(report.diagnostics[0].span,null,
      'unattributable inferred mismatch has no invented location');

    var partialSource='nail 0.54 ; type Option a = None | Some a ; '
      +'def partial = function | Some x -> x ;';
    report=NailSourceAnalysis.analyze(partialSource,boot);
    eq(report.ok,false,'incomplete match rejected by Nail');
    eq(report.diagnostics[0].span.start,partialSource.indexOf('function'),
      'unique original function-pattern site pinpointed');

    var macroSource='nail 0.54 ; type Option a = None | Some a ; '
      +'macro partial x = quote ( match unquote x with '
      +'| Some value -> value ) ;\n'
      +'expand partial ( Some 1 ) ;';
    report=NailSourceAnalysis.analyze(macroSource,boot);
    eq(report.ok,false,'incomplete macro-generated match rejected');
    eq(report.diagnostics[0].span.start,macroSource.indexOf('expand'),
      'macro-generated failure uses unique expansion site');
    eq(report.diagnostics[0].templateSpan.start,
      macroSource.indexOf('match'),'origin retained as related pattern location');

    var multiExpand=macroSource+'\nexpand partial ( Some 2 ) ;';
    report=NailSourceAnalysis.analyze(multiExpand,boot);
    eq(report.diagnostics[0].span.start,multiExpand.indexOf('expand'),
      'failing macro form chooses first invocation of two');
    eq(report.diagnostics[0].span.end,
      multiExpand.indexOf('expand')+'expand'.length,
      'macro site points to the expand keyword, not the complete call');

    var unrelated='nail 0.54 ; type Option a = None | Some a ; '
      +'def partial = function | Some x -> x ; '
      +'macro identity x = quote ( unquote x ) ; '
      +'expand identity ( Some 3 ) ;';
    report=NailSourceAnalysis.analyze(unrelated,boot);
    eq(report.diagnostics[0].span,null,
      'unrelated macro call is never blamed for a source match');
    eq(report.diagnostics[0].templateSpan,null,
      'unrelated macro template does not invent a source origin');

    // Macro provenance must identify the *specific invocation*, not the
    // first matching source token or a guessed globally unique expand call.
    var repeatedGenerated='nail 0.54 ; macro broken x = quote ( missing ) ; '
      +'def first = expand broken 1 ; def second = expand broken 2 ;';
    report=NailSourceAnalysis.analyze(repeatedGenerated,boot);
    eq(report.ok,false,'macro template unknown name rejected');
    eq(report.diagnostics[0].span.start,repeatedGenerated.indexOf('expand'),
      'first failing macro invocation is selected among two calls');
    eq(report.diagnostics[0].templateSpan.start,
      repeatedGenerated.indexOf('missing'),
      'generated unknown name retains its original template token');

    var generatedInBranches='nail 0.54 ; macro broken x = quote ( missing ) ; '
      +'def test = if true then expand broken 1 else expand broken 2 ;';
    report=NailSourceAnalysis.analyze(generatedInBranches,boot);
    eq(report.diagnostics[0].span.start,generatedInBranches.indexOf('expand'),
      'same-form repeated macro expansions distinguish the then branch');
    eq(report.diagnostics[0].templateSpan.start,
      generatedInBranches.indexOf('missing'),
      'same-form generated reference retains template origin');

    var holeSource='nail 0.54 ; macro identity x = quote ( unquote x ) ; '
      +'def test = expand identity missing ;';
    report=NailSourceAnalysis.analyze(holeSource,boot);
    eq(report.diagnostics[0].span.start,holeSource.indexOf('missing'),
      'unquoted caller argument retains its own location');
    eq(report.diagnostics[0].templateSpan,null,
      'unquoted caller argument is not falsely attributed to template');

    var secondMacro='nail 0.54 ; '
      +'macro identity x = quote ( unquote x ) ; '
      +'macro broken x = quote ( missing ) ; '
      +'def good = expand identity 1 ; '
      +'def bad = expand broken 2 ;';
    report=NailSourceAnalysis.analyze(secondMacro,boot);
    eq(report.diagnostics[0].span.start,secondMacro.lastIndexOf('expand'),
      'origin isolates second macro with other macro calls and prior forms');
    eq(report.diagnostics[0].templateSpan.start,secondMacro.indexOf('missing'),
      'template origin isolates second macro body');

    var nestedMacro='nail 0.54 ; '
      +'macro inner x = quote ( missing ) ; '
      +'macro outer x = quote ( expand inner ( unquote x ) ) ; '
      +'def broken = expand outer 1 ;';
    report=NailSourceAnalysis.analyze(nestedMacro,boot);
    eq(report.diagnostics[0].span.start,nestedMacro.lastIndexOf('expand'),
      'nested expansion retains outermost user-authored invocation');
    eq(report.diagnostics[0].templateSpan.start,nestedMacro.indexOf('missing'),
      'nested expansion retains inner macro template origin');

    var generatedNumeric='nail 0.54 ; '
      +'macro addOne x = quote ( unquote x + 1 ) ; '
      +'def good = expand addOne 2 ; '
      +'def bad = expand addOne true ;';
    report=NailSourceAnalysis.analyze(generatedNumeric,boot);
    eq(report.ok,false,'invalid generated numeric operator rejected');
    eq(report.diagnostics[0].span.start,generatedNumeric.lastIndexOf('expand'),
      'numeric error resolves to second macro invocation after a valid first');
    eq(report.diagnostics[0].templateSpan.start,generatedNumeric.indexOf('unquote x + 1'),
      'numeric error retains the quoted operator expression origin');

    var repeatedPattern='nail 0.54 ; type Option a = None | Some a ; '
      +'macro partial x = quote ( match unquote x with '
      +'| Some value -> value ) ; '
      +'def broken = if true then expand partial ( Some 1 ) '
      +'else expand partial ( Some 2 ) ;';
    report=NailSourceAnalysis.analyze(repeatedPattern,boot);
    eq(report.ok,false,'generated incomplete pattern in conditional rejected');
    eq(report.diagnostics[0].span.start,repeatedPattern.indexOf('expand'),
      'pattern failure selects first of two macro calls within one form');
    eq(report.diagnostics[0].templateSpan.start,repeatedPattern.indexOf('match'),
      'pattern failure retains exact quoted source pattern');

    // Imported macro diagnostics now own two separate source files. The
    // module's logical import key is the source identity of its template.
    var badModule='nail 0.54 ; macro broken x = quote ( missing ) ; export broken ;';
    var importedSource='nail 0.54 ; import broken from brokenLib ; '
      +'def first = expand broken 1 ; def second = expand broken 2 ;';
    var moduleReads=0;
    var importedResolver=(name:String) -> {
      if (name != 'brokenLib') return null;
      moduleReads++;
      return badModule;
    };
    report=NailSourceAnalysis.analyze(importedSource,boot,importedResolver,
      'src/main.nail');
    eq(report.ok,false,'imported macro type error rejected by Nail bytecode');
    eq(report.diagnostics[0].span.start,importedSource.indexOf('expand'),
      'imported macro selects first failing invocation in caller file');
    eq(report.diagnostics[0].templateSpan,null,
      'foreign macro span must not be mistaken for main source offset');
    eq(report.diagnostics[0].templateOrigin.sourceId,'brokenLib',
      'imported template uses logical module identity');
    eq(report.diagnostics[0].templateOrigin.span.start,
      badModule.indexOf('missing'),'foreign template offset is module-local');
    eq(moduleReads,1,'module source is fetched once across checking and provenance');

    var identityModule='nail 0.54 ; '
      +'macro identity x = quote ( unquote x ) ; export identity ;';
    var importedHole='nail 0.54 ; import identity from identityLib ; '
      +'def bad = expand identity missing ;';
    report=NailSourceAnalysis.analyze(importedHole,boot,
      name -> name == 'identityLib' ? identityModule : null);
    eq(report.ok,false,'bad caller argument still rejected through imported macro');
    eq(report.diagnostics[0].span.start,importedHole.indexOf('missing'),
      'unquote preserves source identity of importing caller');
    eq(report.diagnostics[0].templateOrigin,null,
      'unquoted caller node does not inherit imported template origin');

    var innerModule='nail 0.54 ; macro broken x = quote ( missing ) ; '
      +'export broken ;';
    var outerModule='nail 0.54 ; import broken from innerLib ; '
      +'macro wrapper x = quote ( expand broken ( unquote x ) ) ; '
      +'export wrapper ;';
    var nestedSource='nail 0.54 ; import wrapper from outerLib ; '
      +'def bad = expand wrapper 7 ;';
    var readsInner=0;
    var readsOuter=0;
    report=NailSourceAnalysis.analyze(nestedSource,boot,name -> {
      if (name == 'innerLib') { readsInner++; return innerModule; }
      if (name == 'outerLib') { readsOuter++; return outerModule; }
      return null;
    });
    eq(report.ok,false,'nested imported macro error rejected');
    eq(report.diagnostics[0].span.start,nestedSource.indexOf('expand'),
      'nested imported macro preserves outermost user call');
    eq(report.diagnostics[0].templateOrigin.sourceId,'innerLib',
      'nested imported macro reports actual producing module');
    eq(report.diagnostics[0].templateOrigin.span.start,
      innerModule.indexOf('missing'),'nested imported template points into inner source');
    eq(readsInner,1,'nested inner module loaded once per analysis');
    eq(readsOuter,1,'nested outer module loaded once per analysis');

    var successModule='nail 0.54 ; '
      +'macro identity x = quote ( unquote x ) ; export identity ;';
    var successImport='nail 0.54 ; import identity from utils ; '
      +'expand identity 42 ;';
    report=NailSourceAnalysis.analyze(successImport,boot,
      name -> name == 'utils' ? successModule : null);
    eq(report.ok,true,'Nail checker accepts valid imported expansion');
    eq(report.types,['Int'],'imported code receives Nail-inferred type');

    var missingModule='nail 0.54 ; import identity from nowhere ; '
      +'expand identity 1 ;';
    report=NailSourceAnalysis.analyze(missingModule,boot,
      name -> null);
    eq(report.ok,false,'missing module is reported rather than silently skipped');
    eq(report.diagnostics[0].span,null,
      'module resolver errors do not fabricate source coordinates');

    // Import-aware analysis must NOT erase Nail-only structural aliases,
    // parameter/value annotations or named-relation metadata. They pass
    // through Nail's own typed parser, the macro syntax bridge, and Nail's
    // typed metadata restoration before inference.
    var typedIdentity='nail 0.54 ; macro identity x = quote ( unquote x ) ; '
      +'export identity ;';
    var typedResolver=(name:String) -> name == 'typedHelpers'
      ? typedIdentity : null;

    var numericSpellings='nail 0.54 ; import identity from typedHelpers ; '
      +'expand identity 1 ; expand identity 1.0 ; '
      +'expand identity 2.50 ;';
    report=NailSourceAnalysis.analyze(numericSpellings,boot,typedResolver);
    eq(report.ok,true,'imported macros preserve numerical literal spelling');
    eq(report.types,['Int','Float','Float'],
      'macro syntax conversion cannot silently convert decimal Float to Int');

    var badMixedNumeric='nail 0.54 ; import identity from typedHelpers ; '
      +'expand identity ( 1.0 + 2 ) ;';
    report=NailSourceAnalysis.analyze(badMixedNumeric,boot,typedResolver);
    eq(report.ok,false,
      'imported macro cannot make mixed Int/Float addition look well typed');
    eq(report.diagnostics[0].message.indexOf('No numeric relation instance') >= 0,
      true,'mixed numeric types retain the checker rejection');

    var floatModule='nail 0.54 ; '
      +'macro plusFloat x = quote ( unquote x + 1.0 ) ; '
      +'export plusFloat ;';
    var floatResolver=(name:String) -> name == 'floatMath'
      ? floatModule : null;
    report=NailSourceAnalysis.analyze(
      'nail 0.54 ; import plusFloat from floatMath ; '
      +'expand plusFloat 2.0 ;',boot,floatResolver);
    eq(report.ok,true,
      'imported quoted template preserves Float literal classification');
    eq(report.types,['Float'],
      'Float literal inside module template remains Float after expansion');
    report=NailSourceAnalysis.analyze(
      'nail 0.54 ; import plusFloat from floatMath ; '
      +'expand plusFloat 2 ;',boot,floatResolver);
    eq(report.ok,false,
      'mixed typed literal inside imported template must be rejected');

    var typedHtml='nail 0.54 ; '
      +'import identity from typedHelpers ; '
      +'type Html = { h2 : Text Text , div : Text Text } ; '
      +'def html = { h2 = fun x -> textConcat " H: " x , '
      +'div = fun x -> x } ; '
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'expand identity ( render html " Test " ) ;';
    report=NailSourceAnalysis.analyze(typedHtml,boot,typedResolver);
    eq(report.ok,true,'import preserves structural alias and context block');
    eq(report.types,['Text'],'import + context DSL infers Text in Nail');

    var typedParams='nail 0.54 ; import identity from typedHelpers ; '
      +'type Html = { h2 : Text Text , div : Text Text } ; '
      +'def render ( html : Html ) ( title : Text ) = html { h2 title } ; '
      +'expand identity ( render '
      +'{ h2 = fun x -> x , div = fun x -> x , extra = true } '
      +'" Typed " ) ;';
    report=NailSourceAnalysis.analyze(typedParams,boot,typedResolver);
    eq(report.ok,true,'import preserves multiple typed parameters');
    eq(report.types,['Text'],'multi-annotation source has Text evaluation');

    var typedValue='nail 0.54 ; import identity from typedHelpers ; '
      +'type Html = { h2 : Text Text , div : Text Text } ; '
      +'def html : Html = { h2 = fun x -> x , div = fun x -> x } ; '
      +'expand identity ( html . h2 " Value " ) ;';
    report=NailSourceAnalysis.analyze(typedValue,boot,typedResolver);
    eq(report.ok,true,'import preserves annotated top-level value declaration');
    eq(report.types,['Text'],'annotated value retains projection type');

    var constrained='nail 0.54 ; import identity from typedHelpers ; '
      +'Add : Int Int Int ; Add : Float Float Float ; '
      +'def add x y : Add = x + y ; '
      +'expand identity ( add 6 7 ) ; '
      +'expand identity ( add 1.25 0.5 ) ;';
    report=NailSourceAnalysis.analyze(constrained,boot,typedResolver);
    eq(report.ok,true,'import retains finite named relation signatures');
    eq(report.types,['Int','Float'],'named relation preserves overload choices');

    var rejectedRelation='nail 0.54 ; import identity from typedHelpers ; '
      +'Add : Int Int Int ; def add x y : Add = x + y ; '
      +'expand identity ( add 1.0 2.0 ) ;';
    report=NailSourceAnalysis.analyze(rejectedRelation,boot,typedResolver);
    eq(report.ok,false,'import must not erase relation restrictions');
    eq(report.diagnostics[0].message.indexOf('No relation instance') >= 0,
      true,'Nail rejects unsupported overload under imported macro');

    var rejectedField='nail 0.54 ; import identity from typedHelpers ; '
      +'type Html = { h2 : Text Text , div : Text Text } ; '
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'expand identity ( render { h2 = fun x -> x } " Missing " ) ;';
    report=NailSourceAnalysis.analyze(rejectedField,boot,typedResolver);
    eq(report.ok,false,'import must not erase structural alias contracts');
    eq(report.diagnostics[0].message.indexOf('Missing structural field') >= 0,
      true,'Nail checks the annotated DSL contract after import');

    // Supplying a module capability, even if unused, must not change the
    // behavior of ordinary annotated/DSL programs.
    var localOnly='nail 0.54 ; type Html = { h2 : Text Text } ; '
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'render { h2 = fun x -> x } " Local " ;';
    var localReport=NailSourceAnalysis.analyze(localOnly,boot);
    var moduleReport=NailSourceAnalysis.analyze(localOnly,boot,typedResolver);
    eq(moduleReport.ok,localReport.ok,
      'optional unused resolver does not change typed program acceptance');
    eq(moduleReport.types,localReport.types,
      'optional unused resolver does not change inferred types');

    // Compare the canonical Syntax trees (up to alpha-renaming) produced
    // by the Nail-only expansion and the production Haxe oracle. The
    // comparison preserves free globals, so accidental capture is visible.
    for (body in [
      'macro identity x = quote ( unquote x ) ; expand identity 42 ;',
      'macro addOne x = quote ( unquote x + 1 ) ; expand addOne 41 ;',
      'macro append y = quote ( fun tmp -> tmp + unquote y ) ; '
        +'def tmp = 40 ; ( expand append tmp ) 2 ;',
      'macro inner x = quote ( unquote x + 1 ) ; '
        +'macro outer y = quote ( expand inner ( unquote y ) ) ; '
        +'expand outer 41 ;',
      'macro choose x = quote ( if true then unquote x else 0 ) ; '
        +'expand choose 7 ; expand choose 8 ;',
      'macro choose x = quote ( unquote x ) ; '
        +'if true then expand choose 7 else expand choose 8 ;',
      'macro first x = quote ( unquote x + 1 ) ; '
        +'macro second x = quote ( expand first ( unquote x ) ) ; '
        +'def n = 1 ; expand second n ;',
      'macro constant = quote ( fun arg -> arg ) ; '
        +'( expand constant ) 9 ;',
      'macro applied x = quote ( fun p -> p ) ; '
        +'expand applied 3 4 ;',
      'macro globalRef x = quote ( fun x -> textLength " A " ) ; '
        +'( expand globalRef 1 ) 2 ;'
    ]) compareMacroExpansion(boot,body);

    for (bad in [
      'expand undefined 4 ;',
      'macro invalid x = quote ( unquote unknown ) ; 1 ;',
      'macro named x = quote ( unquote x ) ; '
        +'macro named y = quote ( unquote y ) ; 1 ;',
      'macro bad x = quote ( quote 1 ) ; 1 ;',
      'macro duplicate x x = quote ( unquote x ) ; 1 ;',
      'macro id x = quote ( unquote x ) ; expand id ;',
      'macro self x = quote ( expand self ( unquote x ) ) ; '
        +'expand self 1 ;'
    ]) {
      var input='nail 0.54 ; '+bad;
      var parsed=boot.invoke('modernRewrite',
        boot.invoke('parseSource',Text(input)));
      var hostError=MacroExpander.syntax(parsed);
      var nailError=boot.invoke('nailMacroExpandSyntax',parsed);
      var hostTag=switch(hostError) {
        case SyntaxLeaf(tag,_): tag; case _: '';
      };
      var nailTag=switch(nailError) {
        case SyntaxLeaf(tag,_): tag; case _: '';
      };
      eq(hostTag == 'Error' || hostTag == 'MacroError',true,
        'host rejects invalid macro syntax: '+bad);
      eq(nailTag,hostTag,
        'Nail and host agree on parser or macro rejection: '+bad);
    }

    // Pure Nail expansion fuel is threaded across siblings and *forms*,
    // not reset for each macro call. A tiny limit rejects cumulative work
    // even though every individual macro body is below the limit.
    var fuelSource='nail 0.54 ; '
      +'macro id x = quote ( unquote x ) ; ';
    for (i in 0...24) fuelSource+='expand id '+(i+1)+' ; ';
    var fuelParsed=boot.invoke('modernRewrite',
      boot.invoke('parseSource',Text(fuelSource)));
    var exhausted=boot.invoke('nailMacroExpandSyntaxTinyBudget',fuelParsed);
    eq(switch(exhausted) {
      case SyntaxLeaf('MacroError',text):
        text.indexOf('work limit exceeded') >= 0;
      case _: false;
    },true,'cumulative Nail expansion fuel rejects many simple calls');
    var regular=boot.invoke('nailMacroExpandSyntax',fuelParsed);
    eq(switch(regular) {
      case SyntaxNode('Program',_): true;
      case _: false;
    },true,'normal Nail macro expansion budget accepts moderate programs');
    var tinySingle=boot.invoke('nailMacroExpandSyntaxTinyBudget',
      boot.invoke('modernRewrite',boot.invoke('parseSource',
        Text('nail 0.54 ; macro id x = quote ( unquote x ) ; '
          +'expand id 1 ;'))));
    eq(switch(tinySingle) {
      case SyntaxNode('Program',_): true;
      case _: false;
    },true,'small positive macro expansion fits a tiny budget');

    // The host discovers text imports only, Nail parses their source and
    // resolves exports, lexical definitions, nested imports and expansion.
    var macroModules=new StringMap<String>();
    macroModules.set('arithmetic','nail 0.54 ; '
      +'macro add x = quote ( unquote x + 10 ) ; export add ;');
    macroModules.set('lesson','nail 0.54 ; import add from arithmetic ; '
      +'macro hidden x = quote ( let tmp = 10 in tmp + unquote x ) ; '
      +'macro publicScore x = quote ( expand add ( expand hidden ( unquote x ) ) ) ; '
      +'macro globalScore x = quote ( helper ( unquote x ) ) ; '
      +'export publicScore ; export globalScore ;');
    macroModules.set('identity','nail 0.54 ; '
      +'macro id x = quote ( unquote x ) ; export id ;');
    compareImportedMacro(boot,
      'nail 0.54 ; import add from arithmetic ; '
      +'expand add 1 ; expand add 2 ;',
      macroModules,['Int','Int']);
    compareImportedMacro(boot,
      'nail 0.54 ; import publicScore from lesson ; '
      +'let tmp = 22 in expand publicScore tmp ;',
      macroModules,['Int']);
    compareImportedMacro(boot,
      'nail 0.54 ; import globalScore from lesson ; '
      +'def helper x = x ; let helper = false in expand globalScore 32 ;',
      macroModules,['Int']);
    compareImportedMacro(boot,
      'nail 0.54 ; macro own x = quote ( unquote x + 1 ) ; '
      +'import id from identity ; '
      +'expand id ( expand own 40 ) ;',
      macroModules,['Int']);
    compareImportedMacro(boot,
      'nail 0.54 ; import id from identity ; '
      +'type Html = { h2 : Text Text , div : Text Text } ; '
      +'def html = { h2 = fun x -> x , div = fun x -> x } ; '
      +'def render ( html : Html ) title = html { h2 title } ; '
      +'expand id ( render html " Hello " ) ;',
      macroModules,['Text']);

    var importedApi = 'nail 0.54 ; '
      +'import publicScore from lesson ; '
      +'let tmp = 22 in expand publicScore tmp ;';
    report=NailSourceAnalysis.analyzeNailMacros(importedApi,boot,
      name -> macroModules.get(name),'src/imported-api.nail');
    eq(report.ok,true,'public opt-in Nail module checker accepts transitive macros');
    eq(report.types,['Int'],'public opt-in Nail module checker infers Int');

    var importedBroken='nail 0.54 ; '
      +'macro broken x = quote ( missing ) ; export broken ;';
    macroModules.set('brokenLib',importedBroken);
    var brokenCall='nail 0.54 ; import broken from brokenLib ; '
      +'expand broken 1 ; expand broken 2 ;';
    report=NailSourceAnalysis.analyzeNailMacros(brokenCall,boot,
      name -> macroModules.get(name),'src/with-broken.nail');
    eq(report.ok,false,'Nail macro analyzer rejects imported unknown identifier');
    eq(report.diagnostics[0].templateOrigin.sourceId,'brokenLib',
      'Nail imported failure still maps to the defining source module');
    eq(report.diagnostics[0].span.start,brokenCall.indexOf('expand'),
      'Nail imported failure uses first call site');

    // A diamond import graph forces repeated requests for the same module.
    // The Nail resolution cache must contain each completed export table once.
    macroModules.set('base','nail 0.54 ; '
      +'macro identity x = quote ( unquote x ) ; export identity ;');
    macroModules.set('left','nail 0.54 ; '
      +'import identity from base ; '
      +'macro fromLeft x = quote ( expand identity ( unquote x ) ) ; '
      +'export fromLeft ;');
    macroModules.set('right','nail 0.54 ; '
      +'import identity from base ; '
      +'macro fromRight x = quote ( expand identity ( unquote x ) ) ; '
      +'export fromRight ;');
    var diamond='nail 0.54 ; import fromLeft from left ; '
      +'import fromRight from right ; '
      +'expand fromLeft 41 ; expand fromRight 42 ;';
    compareImportedMacro(boot,diamond,macroModules,['Int','Int']);
    var diamondModules=NailMacroModuleInputs.collect(boot,diamond,
      name -> macroModules.get(name));
    var preparedCache=boot.invoke('nmPrepareModules',diamondModules);
    eq(switch(preparedCache) {
      case SyntaxNode('NMCachedModules',items):
        var count=0;
        var rest=items;
        while (true) switch(rest) {
          case Cons(_,tail): count++; rest=tail;
          case Nil: break;
          case _: throw 'Malformed Nail macro cache';
        }
        count;
      case _: -1;
    },3,'diamond import yields one cached export table per source module');
    var duplicateExports=boot.invoke('nmPrepareModules',diamondModules);
    eq(normalizedMacro(preparedCache,new StringMap<String>(),0),
      normalizedMacro(duplicateExports,new StringMap<String>(),0),
      'Nail export resolution remains deterministic across repeated requests');
    var diamondResolverCalls=new StringMap<Int>();
    var countedDiamond=NailMacroModuleInputs.collect(boot,diamond,
      name -> {
        var count=diamondResolverCalls.exists(name)
          ? diamondResolverCalls.get(name) : 0;
        diamondResolverCalls.set(name,count+1);
        return macroModules.get(name);
      });
    eq(normalizedMacro(countedDiamond,new StringMap<String>(),0),
      normalizedMacro(diamondModules,new StringMap<String>(),0),
      'counted source discovery yields the same diamond module table');
    for (name in ['base','left','right'])
      eq(diamondResolverCalls.get(name),1,
        'diamond resolver loads '+name+' exactly once per analysis');

    var wideImportedSource='nail 0.54 ; import add from arithmetic ; ';
    for (i in 0...24) wideImportedSource+='expand add '+(i+1)+' ; ';
    var wideImportedProgram=NailMacroModuleInputs.parsedModern(
      boot,wideImportedSource);
    var wideImportedModules=NailMacroModuleInputs.collect(
      boot,wideImportedSource,name -> macroModules.get(name),
      wideImportedProgram);
    var budgetRequest=NailMacroModuleInputs.request(
      wideImportedProgram,wideImportedModules);
    var outOfFuel=boot.invoke('nailMacroExpandWithModulesTinyBudget',
      budgetRequest);
    eq(switch(outOfFuel) {
      case SyntaxLeaf('MacroError',message):
        message.indexOf('work limit exceeded') >= 0;
      case _: false;
    },true,'imported macro calls share one global work budget');
    eq(switch(boot.invoke('nailMacroExpandWithModules',budgetRequest)) {
      case SyntaxNode('Program',_): true;
      case _: false;
    },true,'normal expansion budget accepts repeated imports');

    var largeModule='nail 0.54 ; ';
    for (i in 0...100)
      largeModule+='macro filler'+i+' = quote ( '+i+' ) ; ';
    largeModule+='export filler0 ;';
    macroModules.set('large',largeModule);
    var largeMain='nail 0.54 ; import filler0 from large ; expand filler0 ;';
    var largeModules=NailMacroModuleInputs.collect(boot,largeMain,
      name -> macroModules.get(name));
    var largeRequest=NailMacroModuleInputs.request(
      NailMacroModuleInputs.parsedModern(boot,largeMain),largeModules);
    eq(switch(boot.invoke('nailMacroExpandWithModulesTinyBudget',
        largeRequest)) {
      case SyntaxLeaf('MacroError',message):
        message.indexOf('work limit exceeded') >= 0;
      case _: false;
    },true,'preflight work charge includes imported module declarations');

    // Single-pass per-node source maps are parallel to the canonical
    // expanded Program. The checker uses the original AST, never NMTrace.
    var numericMacro='nail 0.54 ; '
      +'macro add x = quote ( unquote x + 1 ) ; '
      +'expand add " text " ;';
    var numericPrepared=boot.invoke('tcPrepareTypedSource',
      Text(numericMacro));
    var numericProgram=switch(numericPrepared) {
      case SyntaxNode('TCPreparedMacros',Cons(p,_)): p;
      case _: throw 'Could not parse numeric provenance test';
    };
    var numericRequest=NailMacroModuleInputs.request(numericProgram,
      SyntaxNode('NMModules',Nil));
    var tracedExpansion=boot.invoke('nailMacroExpandWithModulesTraced',
      numericRequest);
    var tracedProgram=switch(tracedExpansion) {
      case SyntaxNode('NMExpansionTraced',Cons(program,_)): program;
      case _: throw 'Expected Nail expansion+provenance pair';
    };
    var tracedOrigins=switch(tracedExpansion) {
      case SyntaxNode('NMExpansionTraced',Cons(_,Cons(traces,Nil))): traces;
      case _: throw 'Expected Nail parallel origin sidecar';
    };
    eq(normalizedMacro(tracedProgram,new StringMap<String>(),0),
      normalizedMacro(boot.invoke('nailMacroExpandWithModules',
        numericRequest),new StringMap<String>(),0),
      'trace-enabled and untraced Nail macro expansion have identical AST');
    var numericChecked=boot.invoke('tcCheckExpandedTypedTraced',
      SyntaxNode('TCExpansionRequest',
        Cons(numericPrepared,Cons(tracedProgram,Nil))));
    eq(ResultValue.tag(numericChecked),ResultValue.ERR,
      'generated numeric type mismatch is rejected by Nail');
    var numericOrigin=boot.invoke('nmFaultNodeOrigin',
      SyntaxNode('NMTraceRequest',Cons(tracedOrigins,
        Cons(ResultValue.get(numericChecked,ResultValue.ERR),Nil))));
    eq(switch(numericOrigin) {
      case SyntaxNode('NMSource',Cons(
          SyntaxLeaf('Name',owner),Cons(
          SyntaxLeaf('Name',macroName),Cons(
          SyntaxLeaf('Name',path),Cons(
          SyntaxLeaf('Name',callPath),Nil))))):
        owner == '#caller' && macroName == 'add' && path == ''
          && callPath == '';
      case _: false;
    },true,'traced numeric operation points to its exact macro template AST root');

    var numericReport=NailSourceAnalysis.analyzeNailMacros(
      numericMacro,boot,null,'src/numeric-template.nail');
    eq(numericReport.ok,false,'Nail reports generated numeric mismatch');
    eq(numericReport.diagnostics[0].templateOrigin.sourceId,
      'src/numeric-template.nail',
      'numeric mismatch has original local macro source identity');
    eq(numericReport.diagnostics[0].templateOrigin.span.start,
      numericMacro.indexOf(' + ')+1,
      'generated numeric mismatch identifies exact template operator');
    eq(numericReport.diagnostics[0].span.start,
      numericMacro.indexOf('expand'),
      'generated numeric mismatch identifies original call site');

    // Multiple macro invocations in one form are distinguished by the
    // original structural call path, even for the same macro name.
    var distinctCalls='nail 0.54 ; '
      +'macro good x = quote ( unquote x ) ; '
      +'macro bad x = quote ( unquote x + 1 ) ; '
      +'( expand good 7 ) + ( expand bad " text " ) ;';
    var distinctReport=NailSourceAnalysis.analyzeNailMacros(
      distinctCalls,boot,null,'src/distinct-calls.nail');
    eq(distinctReport.ok,false,
      'mixed source form contains a failing generated numeric expression');
    eq(distinctReport.diagnostics[0].span.start,
      distinctCalls.lastIndexOf('expand bad'),
      'multiple distinct calls map to the responsible macro keyword');
    eq(distinctReport.diagnostics[0].templateOrigin.sourceId,
      'src/distinct-calls.nail',
      'distinct macro call retains its local template identity');
    eq(distinctReport.diagnostics[0].templateOrigin.span.start,
      distinctCalls.indexOf(' + 1')+1,
      'distinct macro call points to failing numeric operator');

    var duplicateCall='nail 0.54 ; '
      +'macro bad x = quote ( unquote x + 1 ) ; '
      +'( expand bad 2 ) + ( expand bad " text " ) ;';
    var duplicateReport=NailSourceAnalysis.analyzeNailMacros(
      duplicateCall,boot,null,'src/duplicate-calls.nail');
    eq(duplicateReport.ok,false,
      'duplicate macro calls in one form produce a type error');
    eq(duplicateReport.diagnostics[0].span.start,
      duplicateCall.lastIndexOf('expand bad'),
      'structural path identifies the second call to the same macro');

    var firstBadCall='nail 0.54 ; '
      +'macro bad x = quote ( unquote x + 1 ) ; '
      +'( expand bad " text " ) + ( expand bad 2 ) ;';
    var firstBadReport=NailSourceAnalysis.analyzeNailMacros(
      firstBadCall,boot,null,'src/first-duplicate.nail');
    eq(firstBadReport.ok,false,'first of identical macro calls fails');
    eq(firstBadReport.diagnostics[0].span.start,
      firstBadCall.indexOf('expand bad'),
      'caller path also identifies the first duplicate call');


    // The Nail-projected map retains original lexical order and full paths,
    // even with both nested and repeated calls in the same expression.
    var callOrderSource='nail 0.54 ; '
      +'( expand outer ( expand inner 1 ) ) + ( expand outer 2 ) ;';
    var callOrderParsed=boot.invoke('modernRewrite',
      boot.invoke('parseSource',Text(callOrderSource)));
    var callOrderExpression=switch(callOrderParsed) {
      case SyntaxNode('Program',Cons(
          SyntaxNode('Evaluate',Cons(expr,Nil)),Nil)): expr;
      case _: throw 'Expected original expression for Nail call order test';
    };
    var callOrderMap=boot.invoke('nmSourceCallTokens',callOrderExpression);
    var mappedCalls:Array<String>=[];
    switch(callOrderMap) {
      case SyntaxNode('NMTokenMap',nodes):
        var remaining:Value=nodes;
        while (true) switch(remaining) {
          case Cons(SyntaxNode('NMTokenOrigin',Cons(
              SyntaxLeaf('Name',path),Cons(
              SyntaxLeaf('Name',name),Nil))),tail):
            mappedCalls.push(path+':'+name);
            remaining=tail;
          case Nil: break;
          case _: throw 'Malformed Nail call-order token map';
        }
      case _: throw 'Expected Nail call-order token map';
    }
    eq(mappedCalls,['01:outer','011:inner','1:outer'],
      'Nail source call map preserves nested arguments and duplicate names');

    var nestedArguments='nail 0.54 ; '
      +'macro identity x = quote ( unquote x ) ; '
      +'macro add x = quote ( unquote x + 1 ) ; '
      +'( expand identity ( expand add 2 ) ) + '
      +'( expand add " text " ) ;';
    var nestedArgumentReport=NailSourceAnalysis.analyzeNailMacros(
      nestedArguments,boot,null,'src/nested-expand-arguments.nail');
    eq(nestedArgumentReport.ok,false,
      'nested macro arguments and repeated calls are checked in Nail');
    eq(nestedArgumentReport.diagnostics[0].span.start,
      nestedArguments.lastIndexOf('expand add'),
      'Nail caller-token map selects invalid repeated macro expansion');


    // A typed source includes both an erased macro declaration and ordinary
    // forms (including a sum declaration). The macro call's form ordinal is
    // counted only among source forms retained by the checker.
    var formOrderSource='nail 0.54 ; type Choice = A | B ; '
      +'macro identity x = quote ( unquote x ) ; '
      +'def first = expand identity A ; '
      +'def second = expand identity B ;';
    var formOrderPrepared=boot.invoke('tcPrepareTypedSource',
      Text(formOrderSource));
    var formOrderProgram=switch(formOrderPrepared) {
      case SyntaxNode('TCPreparedMacros',Cons(program,_)): program;
      case _: throw 'Could not prepare source form ordinal fixture';
    };
    var firstFormCalls=boot.invoke('nmSourceCallsInForm',
      SyntaxNode('NMFormCallsRequest',
        Cons(formOrderProgram,Cons(IntNumber(numeric.FastNumber.exact('1')),Nil))));
    var secondFormCalls=boot.invoke('nmSourceCallsInForm',
      SyntaxNode('NMFormCallsRequest',
        Cons(formOrderProgram,Cons(IntNumber(numeric.FastNumber.exact('2')),Nil))));
    var isSingleIdentityCall=(mapped:Value) -> switch(mapped) {
      case SyntaxNode('NMTokenMap',Cons(
          SyntaxNode('NMTokenOrigin',Cons(
            SyntaxLeaf('Name',path),Cons(
            SyntaxLeaf('Name',name),Nil))),Nil)):
        path=='' && name=='identity';
      case _: false;
    };
    eq(isSingleIdentityCall(firstFormCalls),true,
      'Nail form selection excludes macro declaration but counts a sum form');
    eq(isSingleIdentityCall(secondFormCalls),true,
      'Nail form selection identifies second original source definition');
    eq(switch(boot.invoke('nmSourceCallsInForm',
        SyntaxNode('NMFormCallsRequest',
          Cons(formOrderProgram,Cons(IntNumber(numeric.FastNumber.exact('99')),Nil))))) {
      case SyntaxNode('NMTokenMap',_): false;
      case _: true;
    },true,'Nail source form index fails closed when out of bounds');

    var failingSecondForm='nail 0.54 ; '
      +'macro add x = quote ( unquote x + 1 ) ; '
      +'def first = expand add 2 ; '
      +'def second = expand add " wrong " ;';
    var failingSecondFormReport=NailSourceAnalysis.analyzeNailMacros(
      failingSecondForm,boot,null,'src/second-original-form.nail');
    eq(failingSecondFormReport.ok,false,
      'second source form with macro mismatch rejected');
    eq(failingSecondFormReport.diagnostics[0].span.start,
      failingSecondForm.lastIndexOf('expand add'),
      'Nail source form ordinal maps second form to its original caller');

    var nestedDuplicates='nail 0.54 ; '
      +'macro inner x = quote ( unquote x + 1 ) ; '
      +'macro outer x = quote ( expand inner ( unquote x ) ) ; '
      +'( expand outer 2 ) + ( expand outer " text " ) ;';
    var nestedDuplicateReport=NailSourceAnalysis.analyzeNailMacros(
      nestedDuplicates,boot,null,'src/nested-duplicates.nail');
    eq(nestedDuplicateReport.ok,false,
      'nested generated numeric failure among repeated outer calls');
    eq(nestedDuplicateReport.diagnostics[0].span.start,
      nestedDuplicates.lastIndexOf('expand outer'),
      'nested macro retains original outer callsite');
    eq(nestedDuplicateReport.diagnostics[0].templateOrigin.span.start,
      nestedDuplicates.indexOf(' + 1')+1,
      'nested call resolves innermost template operator');

    var nestedNumeric='nail 0.54 ; '
      +'macro bad x = quote ( if true then ( unquote x + 1 ) else 0 ) ; '
      +'expand bad " text " ;';
    var nestedNumericReport=NailSourceAnalysis.analyzeNailMacros(
      nestedNumeric,boot,null,'src/numeric-if.nail');
    eq(nestedNumericReport.ok,false,'Nail rejects invalid branch arithmetic');
    eq(nestedNumericReport.diagnostics[0].templateOrigin.span.start,
      nestedNumeric.indexOf(' + ')+1,
      'checker path maps to numeric operation inside generated if-branch');

    var repeatedOperators='nail 0.54 ; '
      +'macro bad x = quote ( ( 1 + 2 ) + ( unquote x + 3 ) ) ; '
      +'expand bad " text " ;';
    var repeatedOperatorReport=NailSourceAnalysis.analyzeNailMacros(
      repeatedOperators,boot,null,'src/three-operators.nail');
    eq(repeatedOperatorReport.ok,false,
      'generated repeated-operator term fails its type relation');
    eq(repeatedOperatorReport.diagnostics[0].templateOrigin.span.start,
      repeatedOperators.lastIndexOf(' + ')+1,
      'AST source path differentiates repeated operator occurrences');

    var badIf='nail 0.54 ; '
      +'macro bad = quote ( if true then 1 else " text " ) ; '
      +'expand bad ;';
    var badIfReport=NailSourceAnalysis.analyzeNailMacros(
      badIf,boot,null,'src/bad-if.nail');
    eq(badIfReport.ok,false,'branch type mismatch from generated conditional');
    eq(badIfReport.diagnostics[0].templateOrigin.span.start,
      badIf.indexOf('if true'),
      'generated conditional type mismatch points to if token');

    var generatedPattern='nail 0.54 ; type Option a = None | Some a ; '
      +'macro partial x = quote ( match unquote x with '
      +'| Some value -> value ) ; '
      +'expand partial ( Some 1 ) ;';
    var generatedPatternReport=NailSourceAnalysis.analyzeNailMacros(
      generatedPattern,boot,null,'src/generated-pattern.nail');
    eq(generatedPatternReport.ok,false,
      'Nail rejects missing constructor case from a generated pattern');
    eq(generatedPatternReport.diagnostics[0].templateOrigin.sourceId,
      'src/generated-pattern.nail',
      'pattern provenance identifies generated macro owner');
    eq(generatedPatternReport.diagnostics[0].templateOrigin.span.start,
      generatedPattern.indexOf('match'),
      'generated pattern failure identifies the original match token');
    eq(generatedPatternReport.diagnostics[0].span.start,
      generatedPattern.indexOf('expand'),
      'generated pattern failure identifies its caller site');


    // Pattern lowering erases surface 'match' markers. An origin path must
    // select the matching keyword by its AST position, not the first match
    // keyword with the same spelling in a macro template.
    var twoMatches='nail 0.54 ; type Choice = A | B ; '
      +'macro onlySecond x y = quote ( '
      +'( match unquote x with | A -> 1 | B -> 2 ) + '
      +'( match unquote y with | A -> 3 ) ) ; '
      +'expand onlySecond A A ;';
    var secondMatchReport=NailSourceAnalysis.analyzeNailMacros(
      twoMatches,boot,null,'src/two-matches.nail');
    eq(secondMatchReport.ok,false,
      'second of two generated sum matches rejects missing constructor');
    eq(secondMatchReport.diagnostics[0].templateOrigin.span.start,
      twoMatches.lastIndexOf('match'),
      'second generated match resolves its own keyword');
    eq(secondMatchReport.diagnostics[0].span.start,
      twoMatches.indexOf('expand onlySecond'),
      'second generated match preserves caller keyword');

    var firstMatch='nail 0.54 ; type Choice = A | B ; '
      +'macro onlyFirst x y = quote ( '
      +'( match unquote x with | A -> 1 ) + '
      +'( match unquote y with | A -> 3 | B -> 4 ) ) ; '
      +'expand onlyFirst A A ;';
    var firstMatchReport=NailSourceAnalysis.analyzeNailMacros(
      firstMatch,boot,null,'src/first-match.nail');
    eq(firstMatchReport.ok,false,
      'first of two generated sum matches rejects missing constructor');
    eq(firstMatchReport.diagnostics[0].templateOrigin.span.start,
      firstMatch.indexOf('match'),
      'first generated match resolves its own keyword');

    var generatedFunction='nail 0.54 ; type Choice = A | B ; '
      +'macro partial = quote ( function | A -> 1 ) ; '
      +'expand partial ;';
    var functionReport=NailSourceAnalysis.analyzeNailMacros(
      generatedFunction,boot,null,'src/function-pattern.nail');
    eq(functionReport.ok,false,
      'Nail validates exhaustiveness inside a generated function expression');
    eq(functionReport.diagnostics[0].templateOrigin.span.start,
      generatedFunction.indexOf('function'),
      'generated function-pattern failure maps to its function keyword');


    // Nail emits constructor-specific paths before inferring lowered match.
    var mixedCase='nail 0.54 ; '
      +'type First = One ; type Second = Other ; '
      +'macro mixed x = quote ( match unquote x with '
      +'| One -> 1 | Other -> 2 ) ; expand mixed One ;';
    var mixedReport=NailSourceAnalysis.analyzeNailMacros(
      mixedCase,boot,null,'src/mixed-branch.nail');
    eq(mixedReport.ok,false,'mixed sum owners rejected');
    eq(mixedReport.diagnostics[0].templateOrigin.span.start,
      mixedCase.indexOf('| Other')+2,
      'mixed owner failure points to the offending constructor');
    eq(mixedReport.diagnostics[0].span.start,
      mixedCase.indexOf('expand mixed'),
      'mixed owner failure keeps original call site');

    var unknownCase='nail 0.54 ; type Option a = None | Some a ; '
      +'macro broken x = quote ( match unquote x with '
      +'| None -> 0 | Ghost item -> item ) ; expand broken None ;';
    var unknownReport=NailSourceAnalysis.analyzeNailMacros(
      unknownCase,boot,null,'src/unknown-branch.nail');
    eq(unknownReport.ok,false,'unknown sum constructor rejected');
    eq(unknownReport.diagnostics[0].templateOrigin.span.start,
      unknownCase.indexOf('Ghost'),
      'unknown constructor selects actual offending branch');

    var repeatedCases='nail 0.54 ; type Option a = None | Some a ; '
      +'macro secondArity x y = quote ( '
      +'( match unquote x with | None -> 0 | Some value -> value ) + '
      +'( match unquote y with | None -> 0 | Some -> 1 ) ) ; '
      +'expand secondArity ( Some 1 ) ( Some 2 ) ;';
    var repeatedCaseReport=NailSourceAnalysis.analyzeNailMacros(
      repeatedCases,boot,null,'src/repeated-constructors.nail');
    eq(repeatedCaseReport.ok,false,'incorrect constructor binder arity rejected');
    eq(repeatedCaseReport.diagnostics[0].templateOrigin.span.start,
      repeatedCases.indexOf('| Some ->')+2,
      'repeated Some case identifies the second occurrence');


    // These patterns require source-order recovery from nested lowered
    // expressions; the ordering is now computed in Nail, not in Haxe.
    var nestedSecond='nail 0.54 ; type Choice = A | B ; '
      +'macro nested x = quote ( match unquote x with '
      +'| A -> ( match A with | A -> 1 ) | B -> 2 ) ; '
      +'expand nested A ;';
    var nestedSecondReport=NailSourceAnalysis.analyzeNailMacros(
      nestedSecond,boot,null,'src/nested-pattern-branch.nail');
    eq(nestedSecondReport.ok,false,
      'nested incomplete pattern in a generated constructor branch rejected');
    eq(nestedSecondReport.diagnostics[0].templateOrigin.span.start,
      nestedSecond.lastIndexOf('match'),
      'Nail-authored token map identifies the inner branch match');

    var nestedScrutinee='nail 0.54 ; type Choice = A | B ; '
      +'macro nestedSubject x = quote ( '
      +'match ( match unquote x with | A -> A ) with '
      +'| A -> 1 | B -> 2 ) ; '
      +'expand nestedSubject A ;';
    var nestedScrutineeReport=NailSourceAnalysis.analyzeNailMacros(
      nestedScrutinee,boot,null,'src/nested-pattern-subject.nail');
    eq(nestedScrutineeReport.ok,false,
      'nested incomplete pattern inside outer scrutinee rejected');
    eq(nestedScrutineeReport.diagnostics[0].templateOrigin.span.start,
      nestedScrutinee.lastIndexOf('match'),
      'Nail-authored token map identifies scrutinee match in source order');


    // Numeric infix and authored conditional order now come from Nail.
    var twoIfs='nail 0.54 ; '
      +'macro bad x = quote ( '
      +'( if true then 1 else 2 ) + '
      +'( if true then 3 else unquote x ) ) ; '
      +'expand bad " text " ;';
    var twoIfsReport=NailSourceAnalysis.analyzeNailMacros(
      twoIfs,boot,null,'src/repeated-if.nail');
    eq(twoIfsReport.ok,false,'invalid second generated conditional rejected');
    eq(twoIfsReport.diagnostics[0].templateOrigin.span.start,
      twoIfs.lastIndexOf('if true'),
      'Nail token map selects second source-authored if');

    var twoMultiplies='nail 0.54 ; '
      +'macro bad x = quote ( '
      +'( 2 * 3 ) + ( unquote x * 4 ) ) ; '
      +'expand bad " text " ;';
    var twoMultipliesReport=NailSourceAnalysis.analyzeNailMacros(
      twoMultiplies,boot,null,'src/repeated-multiplication.nail');
    eq(twoMultipliesReport.ok,false,
      'invalid second generated multiplication rejected');
    eq(twoMultipliesReport.diagnostics[0].templateOrigin.span.start,
      twoMultiplies.lastIndexOf(' * ')+1,
      'Nail infix traversal identifies second multiplication');

    // Sum-match lowering introduces implicit If nodes that must not be
    // counted as explicit conditional source tokens.
    var matchThenIf='nail 0.54 ; type Choice = A | B ; '
      +'macro bad x = quote ( match unquote x with '
      +'| A -> ( if true then 1 else " text " ) '
      +'| B -> 2 ) ; expand bad A ;';
    var matchThenIfReport=NailSourceAnalysis.analyzeNailMacros(
      matchThenIf,boot,null,'src/match-authored-if.nail');
    eq(matchThenIfReport.ok,false,
      'invalid explicit conditional inside generated match rejected');
    eq(matchThenIfReport.diagnostics[0].templateOrigin.span.start,
      matchThenIf.indexOf('if true'),
      'lowered match predicate does not hide explicit authored if');


    // The last AST source-node interpretation is also Nail-written.
    // It must distinguish a present node with no token from a bad path.
    var directHintTree=SyntaxNode('Apply',Cons(
      SyntaxNode('Apply',Cons(
        SyntaxLeaf('Var','#modern+'),Cons(SyntaxLeaf('Var','left'),Nil))),
      Cons(SyntaxLeaf('Var','right'),Nil)));
    var hintAt=(tree:Value,path:String) ->
      boot.invoke('nmSourceTokenHintAtPath',
        SyntaxNode('NMTokenPathRequest',
          Cons(tree,Cons(SyntaxLeaf('Name',path),Nil))));
    var hintText=(result:Value) -> switch(result) {
      case SyntaxNode('NMSelectedToken',Cons(
          SyntaxLeaf('Name',word),Nil)): word;
      case _: null;
    };
    eq(hintText(hintAt(directHintTree,'')),'+',
      'Nail source node hint recognizes numeric operator');
    eq(hintText(hintAt(directHintTree,'01')),'left',
      'Nail selects the left numeric argument by structural path');
    eq(hintText(hintAt(directHintTree,'1')),'right',
      'Nail selects the right numeric argument by structural path');
    eq(switch(hintAt(directHintTree,'2')) {
      case SyntaxNode('NMSelectedToken',_): true;
      case _: false;
    },false,'Nail rejects out-of-bounds source paths');
    eq(hintText(hintAt(SyntaxLeaf('Var','#macro_global_missing'),'')),
      'missing','Nail token hint strips hygienic global prefix');
    eq(hintText(hintAt(SyntaxLeaf('Var','#macro_local_tmp'),'')),
      null,'Nail never invents a token for a hygienic local variable');


    // Template recovery uses Nail's existing nmParameters and tcFind,
    // not a second Haxe AST walk. Duplicate definitions fail closed.
    var templateSample='nail 0.54 ; '
      +'macro wrap x y = quote ( unquote x + unquote y ) ; '
      +'macro constant = quote ( 7 ) ;';
    var templateProgram=boot.invoke('modernRewrite',
      boot.invoke('parseSource',Text(templateSample)));
    var foreignSource='nail 0.54 ; '
      +'macro foreign x = quote ( unquote x + 1 ) ; export foreign ;';
    var foreignProgram=boot.invoke('modernRewrite',
      boot.invoke('parseSource',Text(foreignSource)));
    var templateModules=SyntaxNode('NMModules',Cons(
      SyntaxNode('TCBinding',Cons(SyntaxLeaf('TCName','external'),
        Cons(foreignProgram,Nil))),Nil));
    var askTemplate=(program:Value,modules:Value,owner:String,name:String) ->
      boot.invoke('nmSourceTemplateInOwner',
        SyntaxNode('NMTemplateOwnerRequest',Cons(program,Cons(modules,
          Cons(SyntaxLeaf('Name',owner),
            Cons(SyntaxLeaf('Name',name),Nil))))));
    var resolvedTemplate=(result:Value) -> switch(result) {
      case SyntaxNode('NMTemplate',Cons(_,Nil)): true;
      case _: false;
    };
    eq(resolvedTemplate(askTemplate(templateProgram,templateModules,
      '#caller','wrap')),true,'Nail extracts two-parameter local template');
    eq(resolvedTemplate(askTemplate(templateProgram,templateModules,
      '#caller','constant')),true,'Nail extracts parameter-free template');
    eq(resolvedTemplate(askTemplate(templateProgram,templateModules,
      'external','foreign')),true,'Nail selects an imported module template');
    eq(resolvedTemplate(askTemplate(templateProgram,templateModules,
      'absent','foreign')),false,'Nail does not invent an absent module');
    eq(resolvedTemplate(askTemplate(templateProgram,templateModules,
      '#caller','missing')),false,'Nail does not invent an absent macro');
    var duplicateTemplateProgram=boot.invoke('modernRewrite',
      boot.invoke('parseSource',Text('nail 0.54 ; '
        +'macro repeated = quote ( 1 ) ; '
        +'macro repeated = quote ( 2 ) ;')));
    eq(resolvedTemplate(askTemplate(duplicateTemplateProgram,templateModules,
      '#caller','repeated')),false,
      'duplicate macro declarations have no guessed template provenance');


    // Nail is the authority for fault-category token policy. Numeric
    // expressions use an ordered AST map; repeated constructor errors
    // cannot borrow a nearby unrelated token.
    var numericFault=SyntaxNode('TCFault',Cons(
      SyntaxLeaf('TCMessage',' No numeric relation instance '),Nil));
    var coverageFault=SyntaxNode('TCFault',Cons(
      SyntaxLeaf('TCMessage','Non-exhaustive match: missing B'),Nil));
    var constructorFault=SyntaxNode('TCFault',Cons(
      SyntaxLeaf('TCMessage','Unknown algebraic constructor in match: X'),
      Nil));
    var projection=(tree:Value,path:String,fault:Value) ->
      boot.invoke('nmSourceDiagnosticProjection',
        SyntaxNode('NMSourceProjectionRequest',
          Cons(tree,Cons(SyntaxLeaf('Name',path),Cons(fault,Nil)))));
    eq(switch(projection(directHintTree,'',numericFault)) {
      case SyntaxNode('NMSourceProjection',Cons(
          SyntaxLeaf('Name','+'),Cons(SyntaxNode('NMTokenMap',_),Nil))): true;
      case _: false;
    },true,'Nail selects arithmetic symbol with structural token map');
    var coverageProjection=projection(directHintTree,'',coverageFault);
    eq(switch(coverageProjection) {
      case SyntaxNode('NMSourceProjection',Cons(
          SyntaxLeaf('Name','match'),Cons(
          SyntaxLeaf('NMNoOrigin',_),Nil))): true;
      case _: false;
    },true,'Nail keeps coverage fallback unique-token-only, got '
      +Std.string(coverageProjection));
    eq(switch(projection(directHintTree,'',constructorFault)) {
      case SyntaxLeaf('NMNoOrigin',_): true;
      case _: false;
    },true,'unknown constructor path cannot borrow a numeric token');
    eq(switch(projection(directHintTree,'9',numericFault)) {
      case SyntaxLeaf('NMNoOrigin',_): true;
      case _: false;
    },true,'unresolvable checker AST path never invents a token');


    // The fused Nail boundary must be *exactly* equivalent to the two
    // original Nail entrypoints, for both valid and rejected source owners.
    // It removes a VM round-trip without changing any diagnostic policy.
    var sourceOwnerRequest=(program:Value,modules:Value,owner:String,
        name:String) ->
      SyntaxNode('NMTemplateOwnerRequest',Cons(program,Cons(modules,
        Cons(SyntaxLeaf('Name',owner),Cons(
          SyntaxLeaf('Name',name),Nil)))));
    var legacyOwnerProjection=(ownerRequest:Value,path:String,fault:Value) ->
      switch(boot.invoke('nmSourceTemplateInOwner',ownerRequest)) {
        case SyntaxNode('NMTemplate',Cons(body,Nil)):
          boot.invoke('nmSourceDiagnosticProjection',
            SyntaxNode('NMSourceProjectionRequest',Cons(body,
              Cons(SyntaxLeaf('Name',path),Cons(fault,Nil)))));
        case _: SyntaxLeaf('NMNoOrigin','');
      };
    var fusedOwnerProjection=(ownerRequest:Value,path:String,fault:Value) ->
      boot.invoke('nmSourceOwnerDiagnosticProjection',
        SyntaxNode('NMSourceOwnerProjectionRequest',
          Cons(ownerRequest,Cons(SyntaxLeaf('Name',path),
            Cons(fault,Nil)))));
    var compareOwnerProjection=(ownerRequest:Value,path:String,
        fault:Value,label:String) -> {
      var oldResult=legacyOwnerProjection(ownerRequest,path,fault);
      var fusedResult=fusedOwnerProjection(ownerRequest,path,fault);
      eq(normalizedMacro(fusedResult,new StringMap<String>(),0),
        normalizedMacro(oldResult,new StringMap<String>(),0),
        'single-vs-two Nail provenance calls: '+label);
    };
    compareOwnerProjection(sourceOwnerRequest(templateProgram,templateModules,
      '#caller','wrap'),'',
      numericFault,'local macro and numeric fault');
    compareOwnerProjection(sourceOwnerRequest(templateProgram,templateModules,
      'external','foreign'),'',
      numericFault,'imported macro and numeric fault');
    compareOwnerProjection(sourceOwnerRequest(templateProgram,templateModules,
      '#caller','constant'),'',
      coverageFault,'zero-parameter template and coverage fault');
    compareOwnerProjection(sourceOwnerRequest(templateProgram,templateModules,
      'external','foreign'),'9',
      numericFault,'unresolvable template path');
    compareOwnerProjection(sourceOwnerRequest(templateProgram,templateModules,
      'absent','foreign'),'',
      numericFault,'missing module');
    compareOwnerProjection(sourceOwnerRequest(duplicateTemplateProgram,
      templateModules,'#caller','repeated'),'',
      numericFault,'duplicate declaration');
    eq(switch(fusedOwnerProjection(SyntaxLeaf('NMNoOrigin',''),'',
        numericFault)) {
      case SyntaxLeaf('NMNoOrigin',_): true;
      case _: false;
    },true,'fused Nail provenance request fails closed on bad owner');

    // Non-gating benchmark on every target. Warm both paths, then alternate
    // execution order to reduce first-run and CI machine drift. We report
    // the median of five samples, plus the raw samples for reproducibility;
    // a VM call reduction is not itself proof of a wall-time speedup.
    var measurementOwner=sourceOwnerRequest(templateProgram,templateModules,
      '#caller','wrap');
    var iterations=64;
    var legacyMeasurement=() ->
      legacyOwnerProjection(measurementOwner,'',numericFault);
    var fusedMeasurement=() ->
      fusedOwnerProjection(measurementOwner,'',numericFault);
    for (i in 0...8) {
      legacyMeasurement();
      fusedMeasurement();
    }
    var measure=(fn:Void->Value) -> {
      var start=haxe.Timer.stamp();
      for (i in 0...iterations) fn();
      return (haxe.Timer.stamp()-start)*1000;
    };
    var legacySamples:Array<Float>=[];
    var fusedSamples:Array<Float>=[];
    for (round in 0...5) {
      if (round%2==0) {
        legacySamples.push(measure(legacyMeasurement));
        fusedSamples.push(measure(fusedMeasurement));
      } else {
        fusedSamples.push(measure(fusedMeasurement));
        legacySamples.push(measure(legacyMeasurement));
      }
    }
    var median=(samples:Array<Float>) -> {
      var ordered=samples.copy();
      ordered.sort((a,b) -> a<b ? -1 : a>b ? 1 : 0);
      return ordered[Std.int(ordered.length/2)];
    };
    trace('Nail provenance VM boundary: 5 samples x '+iterations
      +' cases (warmup 8 per path, alternating order); '
      +'legacy 2 invokes/case vs fused 1 invoke/case; '
      +'median legacy '+Std.string(median(legacySamples))
      +' ms, fused '+Std.string(median(fusedSamples))
      +' ms; samples legacy '+haxe.Json.stringify(legacySamples)
      +', fused '+haxe.Json.stringify(fusedSamples)
      +' (non-gating)');

    var importedNumericSource='nail 0.54 ; '
      +'macro bad x = quote ( unquote x + 1 ) ; export bad ;';
    macroModules.set('numericBad',importedNumericSource);
    var importedNumericCaller='nail 0.54 ; '
      +'import bad from numericBad ; expand bad " text " ;';
    var importedNumericReport=NailSourceAnalysis.analyzeNailMacros(
      importedNumericCaller,boot,name -> macroModules.get(name),
      'src/imported-numeric.nail');
    eq(importedNumericReport.ok,false,
      'imported template with incorrect numeric operand fails');
    eq(importedNumericReport.diagnostics[0].templateOrigin.sourceId,
      'numericBad',
      'numeric failure preserves imported module identity');
    eq(importedNumericReport.diagnostics[0].templateOrigin.span.start,
      importedNumericSource.indexOf(' + ')+1,
      'numeric failure resolves operator inside imported template');
    eq(importedNumericReport.diagnostics[0].span.start,
      importedNumericCaller.indexOf('expand'),
      'imported numeric error retains caller site');


    // v0.55 workload matrix. Vary caller source size and imported module
    // size independently, without changing the failing expression. This
    // isolates the cost of source preparation and module acquisition from
    // macro expansion, HM inference, and source-coordinate projection.
    var localSmall='nail 0.54 ; '
      +'macro bad x = quote ( unquote x + 1 ) ; '
      +'expand bad " text " ;';
    var localWide='nail 0.54 ; '
      +'macro bad x = quote ( unquote x + 1 ) ; ';
    for (i in 0...16)
      localWide+='def helper'+i+' = '+(i+1)+' ; ';
    localWide+='expand bad " text " ;';
    var wideNumericModule='nail 0.54 ; ';
    for (i in 0...24)
      wideNumericModule+='macro filler'+i+' = quote ( '+i+' ) ; ';
    wideNumericModule+='macro bad x = quote ( unquote x + 1 ) ; '
      +'export bad ;';
    macroModules.set('numericWide',wideNumericModule);

    // Isolate the existing two Nail transformations used by every
    // imported source. They must agree structurally with parsedModern;
    // measure the parts rather than assuming a VM boundary dominates.
    for (moduleSample in [
      {label:'small',source:importedNumericSource},
      {label:'wide-24',source:wideNumericModule}
    ]) {
      var expected=NailMacroModuleInputs.parsedModern(
        boot,moduleSample.source);
      var parsedOnce=boot.invoke('parseSource',Text(moduleSample.source));
      var rewrittenOnce=boot.invoke('modernRewrite',parsedOnce);
      eq(normalizedMacro(rewrittenOnce,new StringMap<String>(),0),
        normalizedMacro(expected,new StringMap<String>(),0),
        'module parse/rewrite split is equivalent: '+moduleSample.label);
      var parseSamples:Array<Float>=[];
      var rewriteSamples:Array<Float>=[];
      for (round in 0...5) {
        var startParse=haxe.Timer.stamp();
        var parsed=boot.invoke('parseSource',Text(moduleSample.source));
        parseSamples.push((haxe.Timer.stamp()-startParse)*1000);
        var startRewrite=haxe.Timer.stamp();
        var normalized=boot.invoke('modernRewrite',parsed);
        rewriteSamples.push((haxe.Timer.stamp()-startRewrite)*1000);
        eq(normalizedMacro(normalized,new StringMap<String>(),0),
          normalizedMacro(expected,new StringMap<String>(),0),
          'repeat module parse/rewrite parity: '
          +moduleSample.label+' #'+round);
      }
      trace('Nail 0.55 module stage matrix '+moduleSample.label
        +': five samples, median parse '
        +Std.string(median(parseSamples))+'ms, rewrite '
        +Std.string(median(rewriteSamples))+'ms; parse samples '
        +haxe.Json.stringify(parseSamples)+', rewrite samples '
        +haxe.Json.stringify(rewriteSamples)
        +' (non-gating; same BootRuntime)');
    }
    var profileCases=[
      {label:'local-small',source:localSmall,
        owner:'',template:localSmall},
      {label:'local-wide-caller',source:localWide,
        owner:'',template:localWide},
      {label:'imported-small',source:importedNumericCaller,
        owner:'numericBad',template:importedNumericSource},
      {label:'imported-wide-module',
        source:'nail 0.54 ; import bad from numericWide ; '
          +'expand bad " text " ;',
        owner:'numericWide',template:wideNumericModule}
    ];
    var timedPhases=['prepare','modules','expand','check','result','diagnostic'];
    for (workload in profileCases) {
      var sourceId='src/profile-'+workload.label+'.nail';
      var resolver:Null<String->Null<String>>=workload.owner==''
        ? null : (name:String) -> macroModules.get(name);
      var baseline=NailSourceAnalysis.analyzeNailMacros(
        workload.source,boot,resolver,sourceId);
      eq(baseline.ok,false,'profile workload rejects '+workload.label);
      eq(baseline.diagnostics[0].span.start,
        workload.source.lastIndexOf('expand bad'),
        'profile caller location '+workload.label);
      eq(baseline.diagnostics[0].templateOrigin.sourceId,
        workload.owner=='' ? sourceId : workload.owner,
        'profile template module '+workload.label);
      eq(baseline.diagnostics[0].templateOrigin.span.start,
        workload.template.indexOf(' + ')+1,
        'profile template operator '+workload.label);
      var phaseSeries=new StringMap<Array<Float>>();
      for (name in timedPhases) phaseSeries.set(name,[]);
      var totalSeries:Array<Float>=[];
      for (sample in 0...5) {
        var times=new StringMap<Float>();
        var startFull=haxe.Timer.stamp();
        var measured=NailSourceAnalysis.analyzeNailMacros(
          workload.source,boot,resolver,sourceId,
          (phase,ms) -> times.set(phase,ms));
        totalSeries.push((haxe.Timer.stamp()-startFull)*1000);
        eq(measured,baseline,'profile report parity '
          +workload.label+' #'+sample);
        for (name in timedPhases) {
          eq(times.exists(name),true,
            'profile '+workload.label+' reports '+name);
          phaseSeries.get(name).push(times.get(name));
        }
      }
      var profiledSummary=[for (name in timedPhases)
        name+':'+Std.string(median(phaseSeries.get(name)))+'ms'].join(', ');
      trace('Nail 0.55 diagnostic matrix '+workload.label
        +': five samples, median total '
        +Std.string(median(totalSeries))+'ms; '
        +profiledSummary+'; total samples '
        +haxe.Json.stringify(totalSeries)
        +' (non-gating; same BootRuntime)');
    }

    var importedRepeated='nail 0.54 ; '
      +'import bad from numericBad ; '
      +'( expand bad 2 ) + ( expand bad " text " ) ;';
    var importedRepeatedReport=NailSourceAnalysis.analyzeNailMacros(
      importedRepeated,boot,name -> macroModules.get(name),
      'src/imported-repeated.nail');
    eq(importedRepeatedReport.ok,false,
      'Nail rejects second imported macro call in one form');
    eq(importedRepeatedReport.diagnostics[0].span.start,
      importedRepeated.lastIndexOf('expand bad'),
      'imported same-name macro calls select correct original site');
    eq(importedRepeatedReport.diagnostics[0].templateOrigin.sourceId,
      'numericBad','imported duplicate retains source module identity');

    // Symbolic provenance comes from Nail's own module and lexical scope
    // resolution. The diagnostic sidecar only translates the returned
    // source identity into original token offsets; no Haxe macro replay.
    var localBroken='nail 0.54 ; '
      +'macro broken x = quote ( unknownLocal ) ; '
      +'expand broken 1 ;';
    var localProvenance=NailSourceAnalysis.analyzeNailMacros(
      localBroken,boot,null,'src/local-provenance.nail');
    eq(localProvenance.ok,false,'Nail local generated unknown name rejected');
    eq(localProvenance.diagnostics[0].span.start,
      localBroken.indexOf('expand'),
      'Nail local macro provenance identifies original expansion keyword');
    eq(localProvenance.diagnostics[0].templateOrigin.sourceId,
      'src/local-provenance.nail',
      'Nail provenance names its local defining source');
    eq(localProvenance.diagnostics[0].templateOrigin.span.start,
      localBroken.indexOf('unknownLocal'),
      'Nail provenance resolves original local template identifier');

    var importedBad='nail 0.54 ; '
      +'import broken from brokenLib ; expand broken 1 ;';
    var brokenModule='nail 0.54 ; '
      +'macro broken x = quote ( missingFromModule ) ; '
      +'export broken ;';
    macroModules.set('brokenLib',brokenModule);
    var badModuleReport=NailSourceAnalysis.analyzeNailMacros(
      importedBad,boot,name -> macroModules.get(name),'src/main.nail');
    eq(badModuleReport.ok,false,'Nail imported generated unknown name rejected');
    eq(badModuleReport.diagnostics[0].span.start,
      importedBad.indexOf('expand'),
      'Nail macro provenance preserves caller import callsite');
    eq(badModuleReport.diagnostics[0].templateOrigin.sourceId,'brokenLib',
      'Nail macro provenance owns foreign template module');
    eq(badModuleReport.diagnostics[0].templateOrigin.span.start,
      brokenModule.indexOf('missingFromModule'),
      'Nail macro provenance resolves foreign template identifier');

    var otherFirst='nail 0.54 ; '
      +'import id from identity ; import broken from brokenLib ; '
      +'expand id 3 ; expand broken 1 ;';
    var secondReport=NailSourceAnalysis.analyzeNailMacros(
      otherFirst,boot,name -> macroModules.get(name),'src/two-calls.nail');
    eq(secondReport.ok,false,'Nail checker rejects later failing macro call');
    eq(secondReport.diagnostics[0].span.start,
      otherFirst.indexOf('expand broken'),
      'Nail provenance distinguishes calls in separate source forms');

    var nestedBrokenModule='nail 0.54 ; '
      +'import broken from brokenLib ; '
      +'macro wrapper x = quote ( expand broken ( unquote x ) ) ; '
      +'export wrapper ;';
    macroModules.set('nestedBroken',nestedBrokenModule);
    var nestedBad='nail 0.54 ; import wrapper from nestedBroken ; '
      +'expand wrapper 9 ;';
    var nestedReport=NailSourceAnalysis.analyzeNailMacros(
      nestedBad,boot,name -> macroModules.get(name),
      'src/nested-generated.nail');
    eq(nestedReport.ok,false,'Nail rejects transitive macro template failure');
    eq(nestedReport.diagnostics[0].span.start,nestedBad.indexOf('expand'),
      'Nail trace retains outermost user callsite');
    eq(nestedReport.diagnostics[0].templateOrigin.sourceId,'brokenLib',
      'Nail resolves deepest lexical producer without Haxe expansion');
    eq(nestedReport.diagnostics[0].templateOrigin.span.start,
      brokenModule.indexOf('missingFromModule'),
      'Nail nested origin uses innermost defining module');

    var escapedHole='nail 0.54 ; import id from identity ; '
      +'expand id missingCaller ;';
    var holeReport=NailSourceAnalysis.analyzeNailMacros(
      escapedHole,boot,name -> macroModules.get(name),
      'src/caller-hole.nail');
    eq(holeReport.ok,false,'unquoted caller argument typechecks as original');
    eq(holeReport.diagnostics[0].span.start,
      escapedHole.indexOf('missingCaller'),
      'Nail unquote preserves caller identifier provenance');
    eq(holeReport.diagnostics[0].templateOrigin,null,
      'unquoted caller subtree receives no invented template origin');

    macroModules.set('hidden','nail 0.54 ; '
      +'macro private x = quote ( unquote x ) ; export private ; '
      +'macro notExported x = quote ( unquote x ) ;');
    macroModules.set('reexport','nail 0.54 ; '
      +'import add from arithmetic ; export add ;');
    macroModules.set('a','nail 0.54 ; import b from b ; '
      +'macro a = quote ( 1 ) ; export a ;');
    macroModules.set('b','nail 0.54 ; import a from a ; '
      +'macro b = quote ( 1 ) ; export b ;');
    macroModules.set('runtime','nail 0.54 ; '
      +'def notAllowed = 1 ; macro m = quote ( 1 ) ; export m ;');
    macroModules.set('duplicate','nail 0.54 ; '
      +'macro id x = quote ( unquote x ) ; '
      +'macro id y = quote ( unquote y ) ; export id ;');
    for (bad in [
      'nail 0.54 ; import missing from arithmetic ; expand missing 1 ;',
      'nail 0.54 ; import notExported from hidden ; expand notExported 1 ;',
      'nail 0.54 ; import add from reexport ; expand add 1 ;',
      'nail 0.54 ; import a from a ; expand a ;',
      'nail 0.54 ; import m from runtime ; expand m ;',
      'nail 0.54 ; import id from duplicate ; expand id 2 ;',
      'nail 0.54 ; import id from nowhere ; expand id 2 ;',
      'nail 0.54 ; import add from arithmetic ; '
        +'import add from arithmetic ; expand add 2 ;'
    ]) rejectImportedMacro(boot,bad,macroModules);

    trace('Nail-written typechecker core: '+checks+' differential checks passed');
  }
}
