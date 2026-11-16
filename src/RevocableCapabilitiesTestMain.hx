import haxe.ds.StringMap;
import nail.BootRuntime;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.HostTextGrants;
import nail.ModuleImage;
import nail.ModuleImageTrust;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.ResultValue;
import nail.TextReadCapability;
import nail.TextWriteCapability;
import nail.Value;
import nail.Vm;

/** v0.41: independent per-grant and per-capability revocation. */
class RevocableCapabilitiesTestMain {
  static var passed:Int = 0;
  static function ok(value:Bool, label:String):Void {
    if (!value) throw 'REVOCABLE CAPABILITIES: ' + label;
    passed++;
  }
  static function fails(callback:Void->Void, message:String):Void {
    var got = '';
    try callback() catch (e:Dynamic) got = Std.string(e);
    ok(got.indexOf(message) >= 0,
      'expected "' + message + '", got "' + got + '"');
  }
  static function result(value:Value):String {
    var plain:Dynamic = Vm.toPlain(value);
    return Std.string(Reflect.field(plain, '#tag'))
      + ':' + Std.string(Reflect.field(plain, '#0'));
  }
  static function plainResult(value:Dynamic):String
    return Std.string(Reflect.field(value, '#tag'))
      + ':' + Std.string(Reflect.field(value, '#0'));

  static function readerImage(name:String):String {
    var spec:PublicSourceModuleSpec = {
      name:name,
      source:'def load key = readAsset key ;',
      imports:[{
        module:HostTextGrants.PROVIDER,
        symbol:HostTextGrants.READ_TEXT_RESULT,
        alias:'readAsset',
        scheme:{term:TextReadCapability.resultSignature(),
          quantified:[], comparable:[]}
      }],
      exports:['load']
    };
    return ModuleImage.encode(ModuleLinker.compilePublic(spec));
  }
  static function writerImage(name:String):String {
    var spec:PublicSourceModuleSpec = {
      name:name,
      source:'def save value = writeAsset " song " value ; '
        + 'def reserve key = writeAsset key ;',
      imports:[{
        module:HostTextGrants.PROVIDER,
        symbol:HostTextGrants.WRITE_TEXT_RESULT,
        alias:'writeAsset',
        scheme:{term:TextWriteCapability.signature(),
          quantified:[], comparable:[]}
      }],
      exports:['save','reserve']
    };
    return ModuleImage.encode(ModuleLinker.compilePublic(spec));
  }

  static function testSingleVm(kind:String):Void {
    var calls = 0;
    var reader = new TextReadCapability(['song'], key -> {
      calls++;
      return 'Acoustic';
    });
    var writer = new TextWriteCapability(['song'], (key, content) -> {
      calls++;
      return true;
    });
    var source='readAsset " song " ; writeAsset " song " " value " ;';
    var before:Array<Dynamic>;
    var after:Array<Dynamic>;
    switch(kind) {
      case 'ast':
        var vm = new Vm(40000000);
        vm.grantTextResultReader('readAsset', reader);
        vm.grantTextWriter('writeAsset', writer);
        before = vm.runPlain(source);
        reader.revoke(); writer.revoke();
        after = vm.runPlain(source);
      case 'byte':
        var vm = new ByteVm(40000000);
        vm.grantTextResultReader('readAsset', reader);
        vm.grantTextWriter('writeAsset', writer);
        var compiled = BytecodeCompiler.compileSource(source);
        before = vm.runPlain(compiled);
        reader.revoke(); writer.revoke();
        after = vm.runPlain(compiled);
      case 'boot':
        var vm = new BootRuntime(40000000);
        vm.grantTextResultReader('readAsset', reader);
        vm.grantTextWriter('writeAsset', writer);
        before = vm.runPlain(source);
        reader.revoke(); writer.revoke();
        after = vm.runPlain(source);
      case _: throw 'unknown test runtime';
    }
    ok(plainResult(before[0]) == 'CoreOk:Acoustic'
      && plainResult(before[1]) == 'CoreOk:song',
      kind + ' runs authorized read/write before revocation');
    ok(plainResult(after[0]) == 'CoreErr:revoked'
      && plainResult(after[1]) == 'CoreErr:revoked',
      kind + ' existing imports reject use after instance revocation');
    ok(calls == 2, kind + ' revoked methods never reach host callbacks');
  }

  public static function main():Void {
    for (kind in ['ast','byte','boot']) testSingleVm(kind);

    var store = new StringMap<String>();
    store.set('song','original');
    var readCalls = 0;
    var writeCalls = 0;
    // Intentionally share these objects across consumers. Grant-level
    // revocation must remain isolated by module name, not shared instance.
    var reader = new TextReadCapability(['song'], key -> {
      readCalls++;
      return store.get(key);
    });
    var writer = new TextWriteCapability(['song'], (key, contents) -> {
      writeCalls++;
      store.set(key, contents);
      return true;
    }, 100, 5);
    var grants = new HostTextGrants();
    grants.grantReadText('ReaderA',reader);
    grants.grantReadText('ReaderB',reader);
    grants.grantWriteText('WriterA',writer);
    grants.grantWriteText('WriterB',writer);

    var images = [
      readerImage('ReaderA'), readerImage('ReaderB'),
      writerImage('WriterA'), writerImage('WriterB')
    ];
    var policy = new ModuleImageTrust();
    for (i in 0...images.length)
      policy.pin(['ReaderA','ReaderB','WriterA','WriterB'][i],
        ModuleImageTrust.sha256(images[i]));
    var linked = ModuleLinker.linkTrustedImages(images,policy,40000000,grants);
    ok(result(linked.invoke('ReaderA','load',Text('song')))
      == 'CoreOk:original', 'verified ReaderA works');
    ok(result(linked.invoke('WriterA','save',Text('Samba')))
      == 'CoreOk:song', 'verified WriterA writes');
    ok(store.get('song') == 'Samba', 'authorized change committed');

    // Acquire a curried writer closure before revoking the grant.
    var pending = linked.invoke('WriterA','reserve',Text('song'));
    grants.revokeReadText('ReaderA');
    grants.revokeWriteText('WriterA');
    grants.revokeReadText('ReaderA'); // idempotent
    grants.revokeWriteText('WriterA');

    ok(result(linked.invoke('ReaderA','load',Text('song')))
      == 'CoreErr:revoked', 'ReaderA remains revoked after linking');
    ok(result(linked.invoke('ReaderB','load',Text('song')))
      == 'CoreOk:Samba', 'ReaderB still reads the shared capability');
    ok(result(linked.invoke('WriterA','save',Text('blocked')))
      == 'CoreErr:revoked', 'WriterA cannot write after revocation');
    var attempted = switch(pending) {
      case HostFunction(_, callback): callback(Text('staged write'));
      case _: throw 'expected staged HostFunction';
    };
    ok(result(attempted) == 'CoreErr:revoked',
      'partial application made before grant revocation cannot bypass it');
    ok(store.get('song') == 'Samba' && writeCalls == 1,
      'revoked grant does not mutate or invoke backend');
    ok(result(linked.invoke('WriterB','save',Text('Bachata')))
      == 'CoreOk:song', 'WriterB remains authorized with shared writer');
    ok(store.get('song') == 'Bachata' && writeCalls == 2,
      'other grant can still commit');

    fails(() -> ModuleLinker.linkTrustedImages(images,policy,40000000,grants),
      'revoked text reader grant');
    fails(() -> grants.revokeReadText('Missing'),'missing text reader grant');
    fails(() -> grants.revokeWriteText('Missing'),'missing text writer grant');

    // Instance revocation is deliberately broader than module revocation
    // when a host shares the SAME capability instance.
    reader.revoke();
    writer.revoke();
    ok(result(linked.invoke('ReaderB','load',Text('song')))
      == 'CoreErr:revoked', 'instance revocation reaches all shared readers');
    ok(result(linked.invoke('WriterB','save',Text('blocked')))
      == 'CoreErr:revoked', 'instance revocation reaches all shared writers');
    ok(readCalls == 2 && writeCalls == 2,
      'no callbacks run after shared-object revocation');

    var oldRead = new TextReadCapability(['song'], key -> 'unused');
    var oldValue:Dynamic = Vm.toPlain(oldRead.read(Text('song')));
    ok(Reflect.field(oldValue,'ok') == true,
      'legacy structural reader initially succeeds');
    oldRead.revoke();
    oldValue = Vm.toPlain(oldRead.read(Text('song')));
    ok(Reflect.field(oldValue,'ok') == false
      && Reflect.field(oldValue,'error') == 'revoked',
      'legacy structural ABI retains typed revoked outcome');

    var standaloneWriter = new TextWriteCapability(['song'],
      (key,value) -> {throw 'must not be called'; return true;});
    var half = standaloneWriter.writeKey(Text('song'));
    standaloneWriter.revoke();
    var halfResult = switch(half) {
      case HostFunction(_, cb): cb(Text('denied'));
      case _: throw 'expected staged writer function';
    };
    ok(result(halfResult) == 'CoreErr:revoked',
      'direct capability stage closes over revocation state');

    trace('NailLang v0.41 revocable capability checks: ' + passed + ' passed');
  }
}
