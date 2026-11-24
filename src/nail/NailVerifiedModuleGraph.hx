package nail;

import haxe.ds.StringMap;
import nail.ModuleImage.CompiledModule;
import nail.ModuleLinker.ModuleBundle;

/** Independently pinned Nail sources with provider-produced type/code witnesses. */
typedef PinnedNailProvider = {
  var name:String;
  var source:String;
  var sourceSha256:String;
  var compilerSha256:String;
  var envelope:String;
}

/** Source consumers are checked using only explicitly enumerated modules. */
typedef ExplicitNailConsumer = {
  var name:String;
  var source:String;
  var exports:Array<String>;
  var dependencies:Array<String>;
}

/**
 * A deterministic, explicit dependency graph for trusted checked providers
 * and Haxe/Nail-differentially compiled consumers.
 *
 * Providers are never loaded from received bytecode. Each provider must
 * survive pinned-source rebuilding and cross-checking against the independent
 * Haxe compiler before a public v3 module image is produced.
 *
 * Consumers may refer only to earlier graph nodes that are explicitly named
 * in dependencies. This is not an ambient package resolver or row-polymorphic
 * runtime ABI. No implicit host capability grants can enter this graph.
 */
class NailVerifiedModuleGraph {
  static function fail(message:String):Dynamic
    throw "Nail verified module graph: "+message;

  public static function link(providers:Array<PinnedNailProvider>,
      consumers:Array<ExplicitNailConsumer>,
      maxSteps:Int=ModuleLinker.DEFAULT_STEPS):ModuleBundle {
    if(providers==null || consumers==null
      || providers.length+consumers.length==0
      || providers.length+consumers.length>ModuleLinker.MAX_MODULES)
      fail("invalid module graph size");
    var byName=new StringMap<CompiledModule>();
    var built:Array<CompiledModule>=[];
    function add(module:CompiledModule):Void {
      if(byName.exists(module.name))
        fail("duplicate module "+module.name);
      byName.set(module.name,module);
      built.push(module);
    }
    for(provider in providers) {
      if(provider==null || !ModuleImage.validName(provider.name)
          || byName.exists(provider.name))
        fail("invalid or duplicate provider name");
      add(NailCheckedProviderAdmission.compileClosed(
        provider.name,provider.source,provider.sourceSha256,
        provider.compilerSha256,provider.envelope,maxSteps));
    }
    for(consumer in consumers) {
      if(consumer==null || !ModuleImage.validName(consumer.name)
        || consumer.exports==null || consumer.dependencies==null
        || byName.exists(consumer.name))
        fail("invalid or duplicate consumer");
      var seen=new StringMap<Bool>();
      var dependencies:Array<String>=[];
      for(name in consumer.dependencies) {
        if(!ModuleImage.validName(name) || seen.exists(name) || name==consumer.name)
          fail("invalid or duplicate dependency name");
        seen.set(name,true);
        var dependency=byName.get(name);
        if(dependency==null)
          fail("unknown or forward dependency "+name);
        dependencies.push(ModuleImage.encode(dependency));
      }
      var module=ModuleLinker.compilePublic({
        name:consumer.name, source:consumer.source,
        exports:consumer.exports, dependencies:dependencies
      },maxSteps);
      // Imports must never be supplied by an ambient host provider here.
      for(item in module.imports) {
        if(!seen.exists(item.module))
          fail("import not declared as an explicit dependency");
      }
      add(module);
    }
    return ModuleLinker.link(built,maxSteps);
  }
}
