import haxe.Json;
import haxe.ds.StringMap;
import nail.HostTextGrants;
import nail.ModuleImage;
import nail.ModuleImageTrust;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.TextReadCapability;
import nail.TextWriteCapability;
import nail.Value;
import nail.Vm;

/** v0.40: host-pinned SHA-256 images checked BEFORE module initialization. */
class TrustedModuleImagesTestMain {
  static var passed:Int = 0;

  static function ok(condition:Bool, label:String):Void {
    if (!condition) throw 'TRUSTED MODULES: ' + label;
    passed++;
  }

  static function fails(action:Void->Void, needle:String):Void {
    var message = '';
    try action() catch (error:Dynamic) message = Std.string(error);
    ok(message.indexOf(needle) >= 0,
      'expected "' + needle + '", got "' + message + '"');
  }

  static function writerSource(key:String):String
    return 'def save value = writeAsset " ' + key + ' " value ;';

  static function writerImage(?key:String = 'song'):String {
    var spec:PublicSourceModuleSpec = {
      name:'Saver', source:writerSource(key),
      imports:[{
        module:HostTextGrants.PROVIDER,
        symbol:HostTextGrants.WRITE_TEXT_RESULT,
        alias:'writeAsset',
        scheme:{term:TextWriteCapability.signature(),quantified:[],comparable:[]}
      }],
      exports:['save']
    };
    return ModuleImage.encode(ModuleLinker.compilePublic(spec));
  }

  static function readerImage():String {
    var spec:PublicSourceModuleSpec = {
      name:'Viewer', source:'def load key = readAsset key ;',
      imports:[{
        module:HostTextGrants.PROVIDER,
        symbol:HostTextGrants.READ_TEXT_RESULT,
        alias:'readAsset',
        scheme:{term:TextReadCapability.resultSignature(),quantified:[],comparable:[]}
      }],
      exports:['load']
    };
    return ModuleImage.encode(ModuleLinker.compilePublic(spec));
  }

  public static function main():Void {
    ok(ModuleImageTrust.sha256('abc') ==
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      'SHA-256 reference vector is portable');
    fails(() -> ModuleImageTrust.sha256(null), 'invalid image size');

    var saver = writerImage();
    var viewer = readerImage();
    var store = new StringMap<String>();
    store.set('song', 'original');
    var attempts = 0;
    var grants = new HostTextGrants();
    grants.grantWriteText('Saver',
      new TextWriteCapability(['song'], (key, value) -> {
        attempts++;
        store.set(key,value);
        return true;
      }));
    grants.grantReadText('Viewer',
      new TextReadCapability(['song'],key -> store.get(key)));

    var policy = new ModuleImageTrust();
    policy.pin('Saver', ModuleImageTrust.sha256(saver));
    policy.pin('Viewer', ModuleImageTrust.sha256(viewer));

    ok(policy.verify([viewer,saver]).length == 2,
      'host-approved images verify independently of input order');
    var linked = ModuleLinker.linkTrustedImages([viewer,saver],policy,40000000,grants);
    var written:Dynamic = Vm.toPlain(linked.invoke('Saver','save',Text('Tango 🪕')));
    ok(Reflect.field(written, '#tag') == 'CoreOk' &&
      Reflect.field(written, '#0') == 'song',
      'verified writer module may use an explicitly granted write capability');
    var loaded:Dynamic = Vm.toPlain(linked.invoke('Viewer','load',Text('song')));
    ok(Reflect.field(loaded, '#tag') == 'CoreOk' &&
      Reflect.field(loaded, '#0') == 'Tango 🪕',
      'verified reader observes the completed write');
    ok(attempts == 1, 'approved writer callback invoked exactly once');

    // A valid, recompiled alternative with the SAME self-declared module
    // name must not inherit the host authority of the pinned version.
    var switched = writerImage('other');
    ok(switched != saver,'different source produces a different module image');
    fails(() -> ModuleLinker.linkTrustedImages(
      [viewer,switched],policy,40000000,grants),'unapproved module image');
    ok(attempts == 1 && store.get('song') == 'Tango 🪕',
      'substituted executable cannot reach host callback');

    var spoofed:Dynamic = Json.parse(saver);
    Reflect.setField(spoofed,'name','Viewer');
    var spoofText = Json.stringify(spoofed);
    fails(() -> ModuleLinker.linkTrustedImages(
      [spoofText,viewer],policy,40000000,grants),'unapproved module image');
    ok(attempts == 1,'name spoof cannot borrow another module grant');

    var wronglyBound = new ModuleImageTrust();
    wronglyBound.pin('Viewer',ModuleImageTrust.sha256(saver));
    fails(() -> wronglyBound.verify([saver]),'module name mismatch');
    fails(() -> policy.verify([saver]),'module set mismatch');
    fails(() -> policy.verify([viewer,saver,saver]),'module set mismatch');

    var duplicates = new ModuleImageTrust();
    duplicates.pin('Saver',ModuleImageTrust.sha256(saver));
    duplicates.pin('Viewer',ModuleImageTrust.sha256(viewer));
    fails(() -> duplicates.verify([saver,saver]),'duplicate module image');
    fails(() -> duplicates.pin('Saver',ModuleImageTrust.sha256(viewer)),
      'duplicate module pin');
    fails(() -> duplicates.pin('Another',ModuleImageTrust.sha256(saver)),
      'duplicate image digest');
    fails(() -> duplicates.pin('NailHost',ModuleImageTrust.sha256(saver)),
      'invalid module name');
    fails(() -> duplicates.pin('X','bad-digest'),'invalid SHA-256 digest');
    fails(() -> new ModuleImageTrust().verify([saver]),
      'module set mismatch');

    // Granting a capability never bypasses the checksum/identity gate:
    // a malformed image fails before reading its embedded JSON.
    fails(() -> ModuleLinker.linkTrustedImages(
      ['{',viewer],policy,40000000,grants),'unapproved module image');
    ok(attempts == 1,'invalid input never causes an unexpected write');

    // The direct legacy linkImages API remains available for compatibility.
    // Hosts requiring integrity MUST call linkTrustedImages.
    trace('NailLang v0.40 trusted module image checks: ' + passed + ' passed');
  }
}
