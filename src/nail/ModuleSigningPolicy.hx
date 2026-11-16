package nail;

import haxe.crypto.Base64;
import haxe.ds.StringMap;

/**
 * Pinned publisher keys and the exact expected release are selected by the
 * embedding host, never by the untrusted signed bundle. The keyId is only a
 * local routing hint; trust comes from the independently pinned public key.
 */
class ModuleSigningPolicy {
  public final expectedRelease:String;
  final keys:StringMap<String>;

  public function new(expectedRelease:String) {
    if (!validRelease(expectedRelease))
      throw 'Module signature: invalid expected release';
    this.expectedRelease = expectedRelease;
    this.keys = new StringMap<String>();
  }

  public static function validRelease(value:String):Bool
    return value != null && ~/^v[0-9]+\.[0-9]+(\.[0-9]+)?$/.match(value);

  public static function validKeyId(value:String):Bool
    return value != null && ~/^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/.match(value);

  /** Strict canonical standard Base64. Checks key/signature lengths before
      passing any untrusted content to platform cryptographic libraries. */
  public static function canonicalBase64(raw:String, size:Int):Bool {
    if (raw == null || raw.length < 4 || raw.length > 128 ||
        !~/^[A-Za-z0-9+\/]+={0,2}$/.match(raw)) return false;
    try {
      var bytes = Base64.decode(raw);
      return bytes.length == size && Base64.encode(bytes) == raw;
    } catch (_:Dynamic) {
      return false;
    }
  }

  public function trustKey(keyId:String, publicKeyBase64:String):Void {
    if (!validKeyId(keyId))
      throw 'Module signature: invalid trusted key id';
    if (!canonicalBase64(publicKeyBase64, 32))
      throw 'Module signature: invalid trusted Ed25519 public key';
    if (keys.exists(keyId))
      throw 'Module signature: duplicate trusted key';
    keys.set(keyId, publicKeyBase64);
  }

  public function publicKeyFor(keyId:String):Null<String> {
    return keys.get(keyId);
  }
}
