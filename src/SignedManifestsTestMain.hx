import haxe.Json;
import haxe.crypto.Base64;
import haxe.io.Bytes;
import haxe.ds.StringMap;
import nail.HostTextGrants;
import nail.ModuleImage;
import nail.ModuleImageTrust;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.ModuleSigningPolicy;
import nail.NativeEd25519;
import nail.SignedModuleManifest;
import nail.SignedModuleManifest.SignedModuleEntry;
import nail.TextReadCapability;
import nail.TextWriteCapability;
import nail.Value;
import nail.Vm;

/**
 * The RFC 8032 Ed25519 test-vector seed below is intentionally PUBLIC,
 * exclusively for tests; NEVER deploy it as a trusted signing key.
 * JS uses Node crypto, PHP uses sodium, Haxe --interp invokes Node as a
 * cryptographic test oracle. The production interpreter fails closed unless
 * its embedding host injects a trusted synchronous verifier.
 */
class SignedManifestsTestMain {
  static inline var SEED =
    'nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A=';
  static inline var PUB =
    '11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=';
  static inline var KEY_ID = 'test-vector-DO-NOT-TRUST';
  static var passed:Int = 0;

  static function ok(value:Bool, title:String):Void {
    if (!value) throw 'SIGNED MANIFEST: ' + title;
    passed++;
  }

  static function fails(action:Void->Void, contains:String):Void {
    var actual = '';
    try action() catch (e:Dynamic) actual = Std.string(e);
    ok(actual.indexOf(contains) >= 0,
      'expected "' + contains + '", got "' + actual + '"');
  }

  static function nodeCommand(code:String, args:Array<String>):String {
    #if (js || php)
    throw 'Only the interpreter uses the Node subprocess test oracle';
    #else
    var process = new sys.io.Process('node', ['-e',code].concat(args));
    var output = process.stdout.readAll().toString();
    var errors = process.stderr.readAll().toString();
    var status = process.exitCode();
    process.close();
    if (status != 0) throw 'Ed25519 test oracle failed: ' + errors;
    return StringTools.trim(output);
    #end
  }

  static function sign(payload:String):String {
    #if js
    return cast js.Syntax.code(
      "(function(seed, text) { const c=require('node:crypto'); const der=Buffer.concat([Buffer.from('302e020100300506032b657004220420','hex'),Buffer.from(seed,'base64')]); const privateKey=c.createPrivateKey({key:der,format:'der',type:'pkcs8'}); return c.sign(null, Buffer.from(text,'utf8'),privateKey).toString('base64'); })({0},{1})",
      SEED, payload);
    #elseif php
    return cast php.Syntax.code(
      "base64_encode(sodium_crypto_sign_detached({0}, sodium_crypto_sign_secretkey(sodium_crypto_sign_seed_keypair(base64_decode({1}, true)))))",
      payload, SEED);
    #else
    return nodeCommand(
      "const c=require('node:crypto');const der=Buffer.concat([Buffer.from('302e020100300506032b657004220420','hex'),Buffer.from(process.argv[1],'base64')]);const key=c.createPrivateKey({key:der,format:'der',type:'pkcs8'});process.stdout.write(c.sign(null,Buffer.from(process.argv[2],'base64'),key).toString('base64'));",
      [SEED, Base64.encode(Bytes.ofString(payload))]);
    #end
  }

  static function realVerify(key:String,payload:String,signature:String):Bool {
    #if (js || php)
    return NativeEd25519.verify(key,payload,signature);
    #else
    // Test-only interpreter adapter using Node's REAL Ed25519 primitive.
    // No cryptographic oracle or private key is included in Nail runtime.
    try return nodeCommand(
      "const c=require('node:crypto');const der=Buffer.concat([Buffer.from('302a300506032b6570032100','hex'),Buffer.from(process.argv[1],'base64')]);let valid=false;try{valid=c.verify(null,Buffer.from(process.argv[2],'base64'),{key:der,format:'der',type:'spki'},Buffer.from(process.argv[3],'base64'))}catch(e){}process.stdout.write(valid?'yes':'no');",
      [key,Base64.encode(Bytes.ofString(payload)),signature]) == 'yes'
    catch (_:Dynamic) return false;
    #end
  }

  static function moduleImage(name:String, ?writable:Bool = false,
      ?resource:String = 'song'):String {
    var spec:PublicSourceModuleSpec;
    if (writable) spec = {
      name:name, source:'def save contents = writeAsset " ' + resource + ' " contents ;',
      imports:[{
        module:HostTextGrants.PROVIDER,
        symbol:HostTextGrants.WRITE_TEXT_RESULT,alias:'writeAsset',
        scheme:{term:TextWriteCapability.signature(),quantified:[],comparable:[]}
      }],
      exports:['save']
    };
    else spec = {
      name:name, source:'def load key = readAsset key ;',
      imports:[{
        module:HostTextGrants.PROVIDER,
        symbol:HostTextGrants.READ_TEXT_RESULT,alias:'readAsset',
        scheme:{term:TextReadCapability.resultSignature(),quantified:[],comparable:[]}
      }],
      exports:['load']
    };
    return ModuleImage.encode(ModuleLinker.compilePublic(spec));
  }

  static function entries(images:Array<String>):Array<SignedModuleEntry> {
    var result:Array<SignedModuleEntry> = [];
    for (image in images) {
      var module = ModuleImage.decode(image);
      result.push({name:module.name,sha256:ModuleImageTrust.sha256(image)});
    }
    result.sort((a,b) -> Reflect.compare(a.name,b.name));
    return result;
  }

  static function makeManifest(pins:Array<SignedModuleEntry>,
      ?release:String = 'v0.42',?keyId:String = KEY_ID):String {
    var payload = SignedModuleManifest.canonicalPayload(release,keyId,pins);
    return SignedModuleManifest.encode(release,keyId,pins,sign(payload));
  }

  static function outcome(value:Value):String {
    var plain:Dynamic = Vm.toPlain(value);
    return Std.string(Reflect.field(plain,'#tag')) + ':'
      + Std.string(Reflect.field(plain,'#0'));
  }

  public static function main():Void {
    // RFC 8032 keypair signs arbitrary payload identically on each backend.
    ok(sign('abc') ==
      'gNcksB58omD0zH+N58lfc8+sYVurH3YrZDW27CbIz20sdY2uL4c5mo7tocvNKDWsW6Ztbsqjq6XlZ6dRBT3CBw==',
      'Node and PHP use the same RFC 8032 test private key');
    ok(realVerify(PUB,'abc',sign('abc')),
      'real Ed25519 accepts known valid signature');
    ok(!realVerify(PUB,'abx',sign('abc')),
      'real Ed25519 rejects changed signed payload');
    ok(!NativeEd25519.verify(PUB,'abc','not-base64'),
      'native verifier rejects invalid encoding');

    var saver = moduleImage('Saver',true);
    var viewer = moduleImage('Viewer');
    var pins = entries([saver,viewer]);
    var manifest = makeManifest(pins);
    var policy = new ModuleSigningPolicy('v0.42');
    policy.trustKey(KEY_ID,PUB);
    fails(() -> policy.trustKey(KEY_ID,PUB),'duplicate trusted key');
    fails(() -> policy.trustKey('wrong','bad'),'invalid trusted Ed25519 public key');
    fails(() -> new ModuleSigningPolicy('v01'),'invalid expected release');

    var hostWrites = 0;
    var hostReads = 0;
    var store = new StringMap<String>();
    store.set('song','original');
    var host = new HostTextGrants();
    host.grantReadText('Viewer',new TextReadCapability(['song'],key -> {
      hostReads++;
      return store.get(key);
    }));
    host.grantWriteText('Saver',new TextWriteCapability(['song'],(key,value) -> {
      hostWrites++;
      store.set(key,value);
      return true;
    }));
    var verifiedPins = SignedModuleManifest.verify(manifest,policy,realVerify);
    ok(verifiedPins.verify([viewer,saver]).length == 2,
      'signature produces exact verified module pins');

    var modules = ModuleLinker.linkSignedImagesWithVerifier(
      [viewer,saver],manifest,policy,realVerify,40000000,host);
    ok(outcome(modules.invoke('Saver','save',Text('Jazz 🪕')))
      == 'CoreOk:song','signed module executes with granted writer');
    ok(outcome(modules.invoke('Viewer','load',Text('song')))
      == 'CoreOk:Jazz 🪕','signed modules share only explicit host resources');
    ok(hostWrites == 1 && hostReads == 1,
      'all legitimate callbacks ran once');

    #if (js || php)
    var nativeModules = ModuleLinker.linkSignedImages(
      [saver,viewer],manifest,policy,40000000,host);
    ok(outcome(nativeModules.invoke('Viewer','load',Text('song')))
      == 'CoreOk:Jazz 🪕','default production verifier uses native Ed25519');
    #else
    fails(() -> ModuleLinker.linkSignedImages([saver,viewer],manifest,
      policy,40000000,host),'invalid Ed25519 signature');
    #end

    // Substitute an actually compiled alternate image with the same module
    // name: even a valid signature of the manifest cannot authorize it.
    var substituted = moduleImage('Saver',true,'different');
    fails(() -> ModuleLinker.linkSignedImagesWithVerifier(
      [viewer,substituted],manifest,policy,realVerify,40000000,host),
      'unapproved module image');

    // Every signed metadata field is cryptographically authenticated.
    var forged:Dynamic = Json.parse(manifest);
    Reflect.setField(forged,'release','v0.41');
    fails(() -> SignedModuleManifest.verify(Json.stringify(forged),
      policy,realVerify),'unexpected release');
    Reflect.setField(forged,'release','v0.42');
    Reflect.setField(forged,'keyId','untrusted-key');
    fails(() -> SignedModuleManifest.verify(Json.stringify(forged),
      policy,realVerify),'unknown trusted key');
    Reflect.setField(forged,'keyId',KEY_ID);
    Reflect.setField(forged,'algorithm','SHA256');
    fails(() -> SignedModuleManifest.verify(Json.stringify(forged),
      policy,realVerify),'unsupported manifest format or algorithm');

    Reflect.setField(forged,'algorithm','Ed25519');
    var changed:Array<Dynamic> = cast Reflect.field(forged,'modules');
    Reflect.setField(changed[0],'sha256',
      '0000000000000000000000000000000000000000000000000000000000000000');
    fails(() -> SignedModuleManifest.verify(Json.stringify(forged),
      policy,realVerify),'invalid Ed25519 signature');
    Reflect.setField(forged,'modules',[
      {name:pins[1].name,sha256:pins[1].sha256},
      {name:pins[0].name,sha256:pins[0].sha256}
    ]);
    fails(() -> SignedModuleManifest.verify(Json.stringify(forged),
      policy,realVerify),'unsorted or duplicated modules');

    Reflect.setField(forged,'modules',[
      {name:pins[0].name,sha256:pins[0].sha256},
      {name:pins[0].name,sha256:pins[0].sha256}
    ]);
    fails(() -> SignedModuleManifest.verify(Json.stringify(forged),
      policy,realVerify),'unsorted or duplicated modules');

    Reflect.setField(forged,'modules',[
      {name:pins[0].name,sha256:pins[0].sha256},
      {name:pins[1].name,sha256:pins[1].sha256}
    ]);
    Reflect.setField(forged,'signature','AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==');
    fails(() -> SignedModuleManifest.verify(Json.stringify(forged),
      policy,realVerify),'invalid Ed25519 signature');

    var wrongPolicy = new ModuleSigningPolicy('v0.43');
    wrongPolicy.trustKey(KEY_ID,PUB);
    fails(() -> SignedModuleManifest.verify(manifest,wrongPolicy,realVerify),
      'unexpected release');
    var wrongKey = new ModuleSigningPolicy('v0.42');
    wrongKey.trustKey(KEY_ID,'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
    fails(() -> SignedModuleManifest.verify(manifest,wrongKey,realVerify),
      'invalid Ed25519 signature');

    fails(() -> SignedModuleManifest.verify(manifest,policy,null),
      'missing trusted verifier');
    fails(() -> SignedModuleManifest.verify('not JSON',policy,realVerify),
      'invalid JSON');
    fails(() -> SignedModuleManifest.canonicalPayload('v0.42',KEY_ID,[]),
      'invalid module count');
    fails(() -> SignedModuleManifest.encode('v0.42',KEY_ID,pins,'bad'),
      'invalid detached signature encoding');
    fails(() -> SignedModuleManifest.verify(manifest,policy,
      (key,payload,signature) -> { throw 'sensitive host internals'; return true; }),
      'invalid Ed25519 signature');
    ok(hostWrites == 1 && hostReads == (#if (js || php) 2 #else 1 #end),
      'rejected signatures and images never invoke host callbacks');

    trace('NailLang v0.42 signed manifest checks: '+passed+' passed');
  }
}
