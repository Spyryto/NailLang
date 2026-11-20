package nail;

import haxe.Json;
import haxe.ds.StringMap;
import nail.ModuleImage.CompiledModule;

/**
 * Explicit, independently pinned bridge from a Nail checked-provider witness
 * into the existing public v3 module ABI.
 *
 * The received envelope is NOT executed or loaded. A fresh Nail compiler
 * rebuilds it from trusted source; an independent Haxe checker verifies the
 * same exported schemes; both ordinary compilers regenerate the executable.
 * Only closed schemes that public v3 already supports can be admitted.
 *
 * Do not confuse this with a public open-row ABI or with publisher identity.
 */
class NailCheckedProviderAdmission {
  static function fail(message:String):Dynamic
    throw "Nail provider admission: "+message;

  static function executableSource(source:String):
      {source:String, exports:Array<String>} {
    var tokens=SourcePositions.scan(source);
    var removals:Array<{start:Int,end:Int}>=[];
    var exports:Array<String>=[];
    var seen=new StringMap<Bool>();
    var depth=0;
    var i=0;
    while(i<tokens.length) {
      var t=tokens[i];
      if(depth==0 && t.text=="export"
        && (i==0 || tokens[i-1].text==";")) {
        if(i+2>=tokens.length || tokens[i+2].text!=";"
          || !ModuleImage.validName(tokens[i+1].text))
          fail("invalid top-level export declaration");
        var name=tokens[i+1].text;
        if(seen.exists(name)) fail("duplicate export "+name);
        seen.set(name,true);
        exports.push(name);
        removals.push({start:t.start,end:tokens[i+2].end});
        i+=3;
        continue;
      }
      switch(t.text) {
        case "(" | "[" | "{": depth++;
        case ")" | "]" | "}":
          depth--;
          if(depth<0) fail("malformed source delimiters");
        case _:
      }
      i++;
    }
    if(depth!=0) fail("malformed source delimiters");
    if(exports.length==0) fail("no declared exports");
    var out=new StringBuf();
    var offset=0;
    for(r in removals) {
      out.add(source.substring(offset,r.start));
      var deleted=source.substring(r.start,r.end);
      for(pos in 0...deleted.length) {
        var ch=deleted.charAt(pos);
        out.add(ch=="\n" || ch=="\r" ? ch : " ");
      }
      offset=r.end;
    }
    out.add(source.substring(offset));
    return {source:out.toString(), exports:exports};
  }

  /**
   * Source and compiler pins must arrive independently from a trusted host.
   * Every mismatch throws; no partial module is returned. No host imports,
   * external module dependencies, or structural open rows are admitted here.
   */
  public static function compileClosed(name:String,checkedSource:String,
      expectedSourceSha256:String,expectedCompilerSha256:String,
      receivedEnvelope:String,maxSteps:Int=ModuleLinker.DEFAULT_STEPS)
      :CompiledModule {
    if(!ModuleImage.validName(name) || name==HostTextGrants.PROVIDER)
      fail("invalid module name");
    NailPinnedProviderRebuild.verify(checkedSource,expectedSourceSha256,
      expectedCompilerSha256,receivedEnvelope);
    var declarations=executableSource(checkedSource);
    var envelope:Array<Dynamic>=cast NailCheckedModuleEnvelope.decode(receivedEnvelope);
    var wire:Array<Dynamic>=cast envelope[1];
    var bindings:Array<Dynamic>=cast wire[1];
    if(bindings.length!=declarations.exports.length)
      fail("declared export set differs from checked interface");

    var declared=new StringMap<Bool>();
    for(n in declarations.exports) declared.set(n,true);
    // This is an independent reference check, NOT a row-import shortcut:
    // if Haxe and Nail infer different contracts, fail closed.
    var checker=new TypeChecker();
    checker.check(declarations.source);
    var names:Array<String>=[];
    for(binding in bindings) {
      var pair:Array<Dynamic>=cast binding;
      var symbol:String=cast pair[0];
      if(!declared.exists(symbol))
        fail("checked interface contains undeclared export "+symbol);
      var reference=checker.experimentalCheckedRowPreview(symbol);
      if(reference!=Json.stringify(pair[1]))
        fail("Nail and Haxe disagree on exported scheme "+symbol);
      names.push(symbol);
    }

    // The ordinary v3 compiler enforces its closed-schema restriction and
    // regenerates bytecode with both independent compilers.
    var compiled=ModuleLinker.compilePublic({
      name:name,source:declarations.source,exports:names
    },maxSteps);
    if(compiled.imports.length!=0)
      fail("dependency imports are not admitted in this bridge");
    if(!NailCheckedModuleEnvelope.codeMatches(receivedEnvelope,compiled.code))
      fail("Nail provider witness and independently compiled bytecode disagree");
    return compiled;
  }
}
