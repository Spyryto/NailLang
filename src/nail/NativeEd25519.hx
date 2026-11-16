package nail;

/**
 * Secure native Ed25519 verification on Node.js (crypto) and PHP (sodium).
 * In a browser or a pure Haxe interpreter the default is FAIL CLOSED.
 * Such embedders can inject their own trusted synchronous verifier through
 * ModuleLinker.linkSignedImagesWithVerifier; never accept a permissive stub.
 */
class NativeEd25519 {
  public static function verify(publicKeyBase64:String, message:String,
      signatureBase64:String):Bool {
    if (!ModuleSigningPolicy.canonicalBase64(publicKeyBase64, 32) ||
        !ModuleSigningPolicy.canonicalBase64(signatureBase64, 64))
      return false;
    try {
      #if js
      // RFC 8410 Ed25519 SPKI DER header followed by exactly 32 public bytes.
      // The Node crypto module is unavailable in normal browser contexts,
      // so the exception is caught and verification fails closed.
      return cast js.Syntax.code(
        "require('node:crypto').verify(null, Buffer.from({1}, 'utf8'), {key: Buffer.concat([Buffer.from('302a300506032b6570032100','hex'), Buffer.from({0}, 'base64')]), format: 'der', type: 'spki'}, Buffer.from({2}, 'base64'))",
        publicKeyBase64, message, signatureBase64);
      #elseif php
      return cast php.Syntax.code(
        "function_exists('sodium_crypto_sign_verify_detached') && sodium_crypto_sign_verify_detached(base64_decode({2}, true), {1}, base64_decode({0}, true))",
        publicKeyBase64, message, signatureBase64);
      #else
      return false;
      #end
    } catch (_:Dynamic) {
      return false;
    }
  }
}
