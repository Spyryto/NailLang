package nail;

import haxe.crypto.Sha256;
import haxe.ds.StringMap;
import nail.ModuleImage.CompiledModule;

/**
 * v0.40: an embedding host can independently pin the exact UTF-8 SHA-256
 * of every module image BEFORE decoding and before linking host capabilities.
 *
 * IMPORTANT: A digest is not a digital signature. Pins MUST come from
 * trusted metadata OUTSIDE the untrusted image bundle (e.g. a pinned
 * deployment manifest). Deriving pins from the same downloaded bundle
 * provides no security. No signer identity is inferred from a module name.
 */
class ModuleImageTrust {
  static inline var MAX_IMAGE_LENGTH = 16000000;
  final digestByName:StringMap<String>;
  final nameByDigest:StringMap<String>;
  var count:Int;

  public function new() {
    digestByName = new StringMap<String>();
    nameByDigest = new StringMap<String>();
    count = 0;
  }

  /** Lowercase SHA-256 of exactly the serialized UTF-8 module image bytes.
      The image string is not parsed or executed by this operation. */
  public static function sha256(image:String):String {
    if (image == null || image.length > MAX_IMAGE_LENGTH)
      throw 'Module trust: invalid image size';
    return Sha256.encode(image);
  }

  /** Host-provided name/digest binding. This is a pinned deployment policy,
      NOT an identity assertion from the module itself. */
  public function pin(name:String, digest:String):Void {
    if (!ModuleImage.validName(name) || name == HostTextGrants.PROVIDER)
      throw 'Module trust: invalid module name';
    if (digest == null || !~/^[0-9a-f]{64}$/.match(digest))
      throw 'Module trust: invalid SHA-256 digest';
    if (digestByName.exists(name))
      throw 'Module trust: duplicate module pin';
    if (nameByDigest.exists(digest))
      throw 'Module trust: duplicate image digest';
    digestByName.set(name, digest);
    nameByDigest.set(digest, name);
    count++;
  }

  /** Reject ALL unknown, missing, duplicated or substituted images before
      passing any module bytecode to the linker. Input order is irrelevant.
      The claimed module name must match the host's independent pin. */
  public function verify(images:Array<String>):Array<CompiledModule> {
    if (images == null || images.length == 0 ||
        images.length > ModuleLinker.MAX_MODULES || images.length != count)
      throw 'Module trust: module set mismatch';

    var seen = new StringMap<Bool>();
    var approved:Array<CompiledModule> = [];
    for (image in images) {
      // Match a trusted digest BEFORE parsing metadata or bytecode.
      var trustedName = nameByDigest.get(sha256(image));
      if (trustedName == null)
        throw 'Module trust: unapproved module image';
      if (seen.exists(trustedName))
        throw 'Module trust: duplicate module image';
      var decoded = ModuleImage.decode(image);
      if (decoded.name != trustedName)
        throw 'Module trust: module name mismatch';
      seen.set(trustedName, true);
      approved.push(decoded);
    }
    return approved;
  }
}
