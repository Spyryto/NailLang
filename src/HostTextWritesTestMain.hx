import haxe.Json;
import haxe.ds.StringMap;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.HostTextGrants;
import nail.ModuleImage;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.NType;
import nail.ResultValue;
import nail.TextReadCapability;
import nail.TextWriteCapability;
import nail.TypeChecker;
import nail.TypeScheme;
import nail.Value;
import nail.Vm;

/** v0.39: independent writes with allowlists, quotas and atomic host contract. */
class HostTextWritesTestMain {
  static var passed:Int = 0;
  static function ok(cond:Bool, label:String):Void {
    if (!cond) throw 'TEXT WRITES: ' + label;
    passed++;
  }
  static function fails(run:Void->Void, needle:String):Void {
    var message = '';
    try run() catch (e:Dynamic) message = Std.string(e);
    ok(message.indexOf(needle) >= 0,
      'expected "' + needle + '", got "' + message + '"');
  }
  static function fixture(store:StringMap<String>,
      invoked:Array<String>):TextWriteCapability
    return new TextWriteCapability(['song','blocked','throws'], (key, content) -> {
      invoked.push(key);
      if (key == 'blocked') return false;
      if (key == 'throws') throw 'PRIVATE /host/secrets';
      // This in-memory store performs one synchronous complete replacement.
      store.set(key, content);
      return true;
    }, 14, 2);

  static function runSource():String return
    'def save key value = writeAsset key value ; '
    + 'def describe outcome = match outcome with '
    + '| CoreOk name -> name '
    + '| CoreErr reason -> reason ; '
    + 'describe ( save " song " " Bossa 🪕 " ) ; '
    + 'describe ( save " no " " x " ) ; '
    + 'describe ( save " song " " 12345678901234567890 " ) ; '
    + 'describe ( save " blocked " " rejected " ) ; '
    + 'describe ( save " throws " " failed " ) ; '
    + 'describe ( save " song " " Tango " ) ; '
    + 'describe ( save " song " " Another " ) ;';

  static function expected():String
    return Json.stringify(['song','denied','too-large','not-committed',
      'backend-failure','song','quota-exhausted']);

  static function writeScheme():TypeScheme return {
    term:TextWriteCapability.signature(), quantified:[], comparable:[]
  };
  static function readScheme():TypeScheme return {
    term:TextReadCapability.resultSignature(), quantified:[], comparable:[]
  };
  static function saveSpec():PublicSourceModuleSpec return {
    name:'Saver',
    source:'def save value = writeAsset " song " value ;',
    imports:[{module:HostTextGrants.PROVIDER, symbol:HostTextGrants.WRITE_TEXT_RESULT,
      alias:'writeAsset', scheme:writeScheme()}],
    exports:['save']
  };
  static function readerSpec():PublicSourceModuleSpec return {
    name:'Viewer',
    source:'def load key = readAsset key ;',
    imports:[{module:HostTextGrants.PROVIDER, symbol:HostTextGrants.READ_TEXT_RESULT,
      alias:'readAsset', scheme:readScheme()}],
    exports:['load']
  };
  static function dependentSpec():PublicSourceModuleSpec return {
    name:'Dependent',
    source:'def saveName text = match importedSave text with '
      + '| CoreOk key -> key '
      + '| CoreErr reason -> reason ;',
    imports:[{module:'Saver',symbol:'save',alias:'importedSave',
      scheme:{term:TFunction(TText,TSum('CoreResult',[TText,TText])),
        quantified:[],comparable:[]}}],
    exports:['saveName']
  };

  static function runRuntime(kind:String):Void {
    var store = new StringMap<String>();
    store.set('song','unchanged');
    var seen:Array<String> = [];
    var writer = fixture(store,seen);
    var source = runSource();
    var output:Array<Dynamic>;
    switch(kind) {
      case 'ast':
        var astVm = new Vm(40000000);
        astVm.grantTextWriter('writeAsset',writer);
        output = astVm.runPlain(source);
        fails(() -> astVm.grantTextWriter('writeAsset',fixture(new StringMap(),[])),
          'Duplicate');
      case 'byte':
        var byteVm = new ByteVm(40000000);
        byteVm.grantTextWriter('writeAsset',writer);
        output = byteVm.runPlain(BytecodeCompiler.compileSource(source));
      case 'boot':
        var bootVm = new BootRuntime(40000000);
        bootVm.grantTextWriter('writeAsset',writer);
        output = bootVm.runPlain(source);
        ok(BootstrapImage.encode(BytecodeCompiler.compileSource(source)) ==
          BootstrapImage.encode(bootVm.compile(source)),
          'source-free and reference compilers emit the same write bytecode');
      case _: throw 'Invalid test runtime';
    }
    ok(Json.stringify(output) == expected(),
      kind + ' returns recoverable, sanitized outcomes');
    ok(store.get('song') == 'Tango',
      kind + ' replaces content only after a successful authorized commit');
    ok(!store.exists('no') && !store.exists('blocked') && !store.exists('throws'),
      kind + ' does not mutate unauthorized or rejected resources');
    ok(Json.stringify(seen) == '["song","blocked","throws","song"]',
      kind + ' never invokes callback for denied, oversized, or exhausted requests');
  }

  public static function main():Void {
    var checker = new TypeChecker();
    checker.importSignature('writeAsset', TextWriteCapability.signature());
    ok(checker.signature('writeAsset') == HostTextGrants.WRITE_SIGNATURE,
      'writer signature matches canonical HM checker');
    checker.check(runSource());
    ok(checker.signature('save') == 'Text -> Text -> CoreResult[Text, Text]',
      'curried write remains statically checked and polymorphism-safe');
    fails(() -> new TypeChecker().check(runSource()), 'writeAsset');
    ok(nail.UnicodeText.fitsScalarBudget('a🪕', 2),
      'Unicode budget counts scalars, including non-BMP codepoints');
    ok(!nail.UnicodeText.fitsScalarBudget('a🪕', 1),
      'Unicode budget stops as soon as the scalar limit is exceeded');
    ok(nail.UnicodeText.fitsScalarBudget('', 0),
      'empty Text stays within a zero-scalar admission budget');
    fails(() -> nail.UnicodeText.fitsScalarBudget('a', -1),
      'Invalid Unicode scalar budget');

    var wrong = new TypeChecker();
    wrong.importSignature('writeAsset', TextWriteCapability.signature());
    fails(() -> wrong.check('def bad = writeAsset " song " 42 ;'), 'cannot unify');

    for (backend in ['ast','byte','boot']) runRuntime(backend);
    fails(() -> new Vm().runPlain(runSource()), 'writeAsset');
    fails(() -> new ByteVm().runPlain(BytecodeCompiler.compileSource(runSource())),
      'writeAsset');
    fails(() -> new BootRuntime().runPlain(runSource()), 'writeAsset');
    fails(() -> new TextWriteCapability(['song','song'], (k,v) -> true),
      'duplicate resource name');
    fails(() -> new TextWriteCapability(['../secret'], (k,v) -> true),
      'resource name');
    fails(() -> new TextWriteCapability(['song'], (k,v) -> true, 0),
      'configuration');
    fails(() -> new TextWriteCapability(['song'], (k,v) -> true, 15, 0),
      'configuration');
    fails(() -> new Vm().grantTextWriter('textAt',fixture(new StringMap(),[])),
      'Duplicate');
    fails(() -> new Vm().grantTextWriter('invalid.name',fixture(new StringMap(),[])),
      'Invalid');
    fails(() -> Vm.toPlain(fixture(new StringMap(),[]).asValue()),
      'Cannot serialize function');

    // A denied module cannot acquire the other module's host write grant.
    var saver = ModuleImage.encode(ModuleLinker.compilePublic(saveSpec()));
    var viewer = ModuleImage.encode(ModuleLinker.compilePublic(readerSpec()));
    var dependent = ModuleImage.encode(ModuleLinker.compilePublic(dependentSpec()));
    var decoded = ModuleImage.decode(saver);
    ok(decoded.imports[0].symbol == HostTextGrants.WRITE_TEXT_RESULT &&
      decoded.imports[0].signature == HostTextGrants.WRITE_SIGNATURE,
      'portable image declares explicit typed write dependency');
    ok(decoded.exports[0].signature == 'Text -> CoreResult[Text, Text]',
      'portable image exports typed recoverable writer');

    var store = new StringMap<String>();
    store.set('song','old');
    var seen:Array<String> = [];
    var grants = new HostTextGrants();
    grants.grantWriteText('Saver',fixture(store,seen));
    grants.grantReadText('Viewer',
      new TextReadCapability(['song'],key -> store.get(key)));
    var linked = ModuleLinker.linkImages([dependent, viewer, saver],40000000,grants);
    var saved = Vm.toPlain(linked.invoke('Saver','save',Text('Samba 🪕')));
    ok(Reflect.field(saved,'#tag') == 'CoreOk',
      'writer module returns CoreOk over an independently compiled image');
    ok(store.get('song') == 'Samba 🪕',
      'writer commits a complete replacement into the virtual resource store');
    var readBack = Vm.toPlain(linked.invoke('Viewer','load',Text('song')));
    ok(Reflect.field(readBack,'#tag') == 'CoreOk' &&
      Reflect.field(readBack,'#0') == 'Samba 🪕',
      'read-only module independently observes the completed write');
    ok(Vm.toPlain(linked.invoke('Dependent','saveName',Text('Bachata'))) == 'song',
      'dependent module can use only explicitly imported public writer');
    ok(store.get('song') == 'Bachata',
      'explicit delegation through Saver is allowed');
    ok(Json.stringify(seen) == '["song","song"]',
      'only write-granted callback is invoked on writes');

    var onlyReader = new HostTextGrants();
    onlyReader.grantReadText('Saver',new TextReadCapability(['song'],key -> 'hello'));
    onlyReader.grantReadText('Viewer',new TextReadCapability(['song'],key -> 'hello'));
    fails(() -> ModuleLinker.linkImages([saver],40000000,onlyReader),
      'missing text writer grant');
    var onlyWriter = new HostTextGrants();
    onlyWriter.grantWriteText('Viewer',fixture(new StringMap(),[]));
    fails(() -> ModuleLinker.linkImages([viewer],40000000,onlyWriter),
      'missing text reader grant');
    fails(() -> ModuleLinker.linkImages([saver]), 'missing host grants');

    var wrongSig:PublicSourceModuleSpec = {
      name:'WrongSig',source:'def store key content = writeAsset key content ;',
      imports:[{module:HostTextGrants.PROVIDER,
        symbol:HostTextGrants.WRITE_TEXT_RESULT,alias:'writeAsset',
        scheme:{term:TFunction(TText,TFunction(TText,TText)),
          quantified:[],comparable:[]}}],
      exports:['store']
    };
    var forged = ModuleImage.encode(ModuleLinker.compilePublic(wrongSig));
    var wrongGrants = new HostTextGrants();
    wrongGrants.grantWriteText('WrongSig',fixture(new StringMap(),[]));
    fails(() -> ModuleLinker.linkImages([forged],40000000,wrongGrants),
      'capability type mismatch');

    fails(() -> grants.grantWriteText('Saver',fixture(new StringMap(),[])),
      'duplicate text writer');
    fails(() -> grants.grantWriteText('NailHost',fixture(new StringMap(),[])),
      'invalid module');
    fails(() -> grants.grantWriteText('bad.name',fixture(new StringMap(),[])),
      'invalid module');
    // A host callback which tries a nested write must not start another commit.
    var nested:TextWriteCapability = null;
    var nestedResult:Value = null;
    nested = new TextWriteCapability(['song'],(key,content)->{
      var partly = nested.writeKey(Text('song'));
      nestedResult = switch (partly) {
        case HostFunction(_, callback): callback(Text('reentrant'));
        case _: throw 'Expected pending writer function';
      };
      return true;
    }, 100, 2);
    var top = nested.writeKey(Text('song'));
    var completed = switch (top) {
      case HostFunction(_, callback): callback(Text('top'));
      case _: throw 'Expected writer function';
    };
    ok(ResultValue.is(completed,ResultValue.OK) &&
      ResultValue.is(nestedResult,ResultValue.ERR) &&
      Vm.toPlain(nestedResult) != null,
      'reentrant host callbacks cannot recursively commit');
    trace('NailLang v0.39 controlled write capabilities: ' + passed + ' checks passed');
  }
}
