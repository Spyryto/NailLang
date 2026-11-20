package nail;

import haxe.Resource;
import haxe.crypto.Sha256;
import nail.ResultValue;
import nail.Value;

/**
 * Experimental reproducible-build gate over a checked-provider envelope.
 *
 * Only the embedding host can establish a trusted source digest and trusted
 * compiler bootstrap-image digest through an independent channel. Neither
 * pin is read from the received bundle. No signature or linker authority is
 * conferred on a checked envelope.
 *
 * Rechecks a fresh isolated source-free Nail VM (without host grants), then
 * requires byte-for-byte equality of the complete verified provider envelope.
 * This is a build reproducibility check, not a proof of VM/type-system
 * correctness or authenticated remote publisher identity.
 */
class NailPinnedProviderRebuild {
  public static inline var MAX_SOURCE_BYTES=1000000;
  public static inline var MAX_ENVELOPE_BYTES=16000000;
  public static inline var MAX_STEPS=60000000;

  static function fail(message:String):Dynamic
    throw "Nail pinned provider rebuild: "+message;

  static function validPin(pin:String):Bool
    return pin!=null && ~/^[0-9a-f]{64}$/.match(pin);

  /**
   * Throws on failure, returns no executable module or trusted linker token.
   *
   * The independently trusted pins belong to *source bytes* and *compiler
   * bootstrap image bytes*, not to any claims inside the received envelope.
   */
  public static function verify(source:String,expectedSourceSha256:String,
      expectedCompilerSha256:String,receivedEnvelope:String):Void {
    if(!validPin(expectedSourceSha256) ||
       !validPin(expectedCompilerSha256))
      fail("invalid independent trust pins");
    if(source==null || source.length==0 || haxe.io.Bytes.ofString(source).length>MAX_SOURCE_BYTES)
      fail("invalid trusted source size");
    if(receivedEnvelope==null || receivedEnvelope.length==0 ||
       haxe.io.Bytes.ofString(receivedEnvelope).length>MAX_ENVELOPE_BYTES)
      fail("invalid received envelope size");

    // Host-controlled source is checked before ever invoking untrusted
    // compiler macros; the pinned bootstrap resource is checked before VM
    // startup. A caller deriving both pins from the same untrusted bundle
    // has NOT established provenance.
    if(Sha256.encode(source)!=expectedSourceSha256)
      fail("trusted source digest mismatch");
    var compilerImage=Resource.getString("bootstrap_image");
    if(compilerImage==null ||
       Sha256.encode(compilerImage)!=expectedCompilerSha256)
      fail("trusted compiler image digest mismatch");

    // Reject malformed/corrupted transport before invoking the compiler.
    NailCheckedModuleEnvelope.decode(receivedEnvelope);

    // A new VM has no host capabilities and cannot inherit arbitrary global
    // bindings from any prior dynamic compilation or imported module.
    var compiler=new BootRuntime(MAX_STEPS,compilerImage);
    var checked=compiler.invoke("tcCompileDeclaredModulePreview",
      Text(source));
    if(ResultValue.tag(checked)!=ResultValue.OK)
      fail("trusted source failed checked module compilation");
    var rebuilt=NailCheckedModuleEnvelope.encode(
      ResultValue.get(checked,ResultValue.OK));
    if(rebuilt!=receivedEnvelope)
      fail("received interface or bytecode differs from pinned source build");
  }
}
