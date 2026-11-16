package nail;

import haxe.Json;
import nail.ModuleImage.LinkedModuleImport;

/** A single pinned compiled image with its independently checked digest. */
typedef SignedModuleEntry = {
  var name:String;
  var sha256:String;
}

/**
 * Deterministic, domain-separated Ed25519-signed *deployment* manifest.
 *
 * The signature covers release, key identifier, the exact module count,
 * and each lexicographically ordered name/digest pair. A trusted release
 * expectation and public key MUST originate outside the received bundle.
 * The code never loads a public key embedded in an untrusted manifest.
 */
class SignedModuleManifest {
  public static inline var FORMAT = 'naillang.signed-modules.v1';
  public static inline var ALGORITHM = 'Ed25519';
  static inline var MAX_BYTES = 32768;

  static function validDigest(raw:String):Bool
    return raw != null && ~/^[0-9a-f]{64}$/.match(raw);

  /** ASCII-only canonical payload, stable across Haxe, Node and PHP.
      Entries MUST already be sorted by name, without duplicates. */
  public static function canonicalPayload(release:String, keyId:String,
      entries:Array<SignedModuleEntry>):String {
    if (!ModuleSigningPolicy.validRelease(release) ||
        !ModuleSigningPolicy.validKeyId(keyId))
      throw 'Module signature: invalid manifest identity';
    if (entries == null || entries.length == 0 ||
        entries.length > ModuleLinker.MAX_MODULES)
      throw 'Module signature: invalid module count';

    var lines = [FORMAT, 'release=' + release, 'key=' + keyId,
      'count=' + entries.length];
    var previous:Null<String> = null;
    for (entry in entries) {
      if (entry == null || !ModuleImage.validName(entry.name) ||
          entry.name == HostTextGrants.PROVIDER || !validDigest(entry.sha256))
        throw 'Module signature: invalid module pin';
      if (previous != null && Reflect.compare(previous,entry.name) >= 0)
        throw 'Module signature: unsorted or duplicated modules';
      previous = entry.name;
      lines.push(entry.name + '=' + entry.sha256);
    }
    return lines.join('\n') + '\n';
  }

  /** The producer signs canonicalPayload using a private key that remains
      OUTSIDE NailLang and the published repository. This method merely
      serializes the signed document; it cannot sign or mint trust. */
  public static function encode(release:String,keyId:String,
      entries:Array<SignedModuleEntry>,signatureBase64:String):String {
    canonicalPayload(release,keyId,entries);
    if (!ModuleSigningPolicy.canonicalBase64(signatureBase64,64))
      throw 'Module signature: invalid detached signature encoding';
    return Json.stringify({
      format:FORMAT, algorithm:ALGORITHM, release:release,
      keyId:keyId, modules:[for (item in entries)
        {name:item.name,sha256:item.sha256}],
      signature:signatureBase64
    });
  }

  public static function verify(manifest:String, policy:ModuleSigningPolicy,
      verifier:String->String->String->Bool):ModuleImageTrust {
    if (policy == null)
      throw 'Module signature: missing trusted policy';
    if (verifier == null)
      throw 'Module signature: missing trusted verifier';
    if (manifest == null || manifest.length > MAX_BYTES)
      throw 'Module signature: invalid manifest size';

    var data:Dynamic;
    try data = Json.parse(manifest)
    catch (_:Dynamic) throw 'Module signature: invalid JSON';
    if (data == null || Reflect.field(data,'format') != FORMAT ||
        Reflect.field(data,'algorithm') != ALGORITHM)
      throw 'Module signature: unsupported manifest format or algorithm';

    var release:Dynamic = Reflect.field(data,'release');
    var keyId:Dynamic = Reflect.field(data,'keyId');
    var signature:Dynamic = Reflect.field(data,'signature');
    if (!Std.isOfType(release,String) || !Std.isOfType(keyId,String) ||
        !Std.isOfType(signature,String))
      throw 'Module signature: invalid manifest metadata';
    if (release != policy.expectedRelease)
      throw 'Module signature: unexpected release';
    var publicKey = policy.publicKeyFor(cast keyId);
    if (publicKey == null)
      throw 'Module signature: unknown trusted key';
    if (!ModuleSigningPolicy.canonicalBase64(cast signature,64))
      throw 'Module signature: invalid detached signature encoding';

    var rawModules:Dynamic = Reflect.field(data,'modules');
    if (!Std.isOfType(rawModules,Array))
      throw 'Module signature: invalid module list';
    var values:Array<Dynamic> = cast rawModules;
    if (values.length == 0 || values.length > ModuleLinker.MAX_MODULES)
      throw 'Module signature: invalid module count';
    var entries:Array<SignedModuleEntry> = [];
    for (value in values) {
      if (value == null) throw 'Module signature: invalid module pin';
      var name:Dynamic = Reflect.field(value,'name');
      var digest:Dynamic = Reflect.field(value,'sha256');
      if (!Std.isOfType(name,String) || !Std.isOfType(digest,String))
        throw 'Module signature: invalid module pin';
      entries.push({name:cast name, sha256:cast digest});
    }
    var payload = canonicalPayload(cast release,cast keyId,entries);

    // Do not disclose backend/crypto exception details to Nail code.
    var valid = false;
    try valid = verifier(publicKey,payload,cast signature)
    catch (_:Dynamic) valid = false;
    if (!valid)
      throw 'Module signature: invalid Ed25519 signature';

    var pins = new ModuleImageTrust();
    for (entry in entries) pins.pin(entry.name,entry.sha256);
    return pins;
  }
}
