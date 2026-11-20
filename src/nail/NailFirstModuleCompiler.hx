package nail;

import nail.ModuleImage.CompiledModule;
import nail.ResultValue;
import nail.Value;

/**
 * Opt-in Nail-first compilation of ordinary, isolated source modules.
 *
 * Nail's self-hosted HM checker runs before the public Haxe compiler.
 * On a successful Nail check, the Haxe reference independently checks the
 * complete source and regenerates the module (including bytecode parity).
 * A discrepancy fails closed. Neither compiler trusts the other's result.
 *
 * This initial slice has no runtime imports or ambient capability discovery.
 * A future typed-import prelude may extend it without changing this contract.
 */
class NailFirstModuleCompiler {
  static function fail(message:String):Dynamic
    throw "Nail-first module compiler: "+message;

  public static function compile(name:String,source:String,exports:Array<String>,
      maxSteps:Int=ModuleLinker.DEFAULT_STEPS):CompiledModule {
    if(!ModuleImage.validName(name) || name==HostTextGrants.PROVIDER
      || source==null || exports==null || exports.length==0)
      fail("invalid source module request");
    if(!numeric.LanguageVersion.isModern(source))
      fail("requires explicitly versioned Nail source");

    var isolated=new BootRuntime(maxSteps);
    var result=isolated.invoke("tcCompileCheckedSource",Text(source));
    if(ResultValue.tag(result)!=ResultValue.OK)
      fail("independent Nail checker rejected source: "+
        Std.string(RuntimeValues.toPlain(
          ResultValue.get(result,ResultValue.ERR))));
    var nailCode=ResultValue.get(result,ResultValue.OK);

    // All interfaces, including HM schemes and Eq constraints, must be
    // reproduced independently by the existing, trusted public compiler.
    var compiled=ModuleLinker.compilePublic({
      name:name,source:source,exports:exports
    },maxSteps);
    if(compiled.imports.length!=0)
      fail("runtime imports require the separate explicit module graph");
    if(BootstrapImage.encode(nailCode)!=BootstrapImage.encode(compiled.code))
      fail("Nail-first and reference module bytecode disagree");
    return compiled;
  }
}
