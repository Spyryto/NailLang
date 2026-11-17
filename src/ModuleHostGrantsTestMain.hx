import haxe.Json;
import nail.HostTextGrants;
import nail.ModuleImage;
import nail.ModuleLinker;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.TextReadCapability;
import nail.TypeChecker;
import nail.TypeScheme;
import nail.Value;
import nail.Vm;

/** A capability is a typed import, not an ambient service or fake Nail module. */
class ModuleHostGrantsTestMain {
  static var passed = 0;

  static function ok(condition:Bool, label:String):Void {
    if (!condition) throw 'MODULE HOST GRANTS: ' + label;
    passed++;
  }

  static function fails(task:Void->Void, needle:String):Void {
    var message = '';
    try task() catch (e:Dynamic) message = Std.string(e);
    ok(message.indexOf(needle) >= 0, 'expected "' + needle + '", got "' + message + '"');
  }

  static function source():String return
    'def lookup key = let reply = readAsset key in '
    + 'if reply . ok then reply . value else reply . error ;';

  static function contract():TypeScheme return {
    term:TextReadCapability.signature(), quantified:[], comparable:[]
  };

  static function spec(name:String, ?symbol:String = 'readText',
      ?scheme:TypeScheme):PublicSourceModuleSpec return {
    name:name, source:source(),
    imports:[{module:HostTextGrants.PROVIDER, symbol:symbol,
      alias:'readAsset', scheme:scheme == null ? contract() : scheme}],
    exports:['lookup']
  };

  static function encode(name:String, ?symbol:String = 'readText',
      ?scheme:TypeScheme):String
    return ModuleImage.encode(ModuleLinker.compilePublic(spec(name, symbol, scheme)));

  static function grants(seenLeft:Array<String>, seenRight:Array<String>):HostTextGrants {
    var result = new HostTextGrants();
    result.grantReadText('Left', new TextReadCapability(['left'], key -> {
      seenLeft.push(key);
      return 'L: 🪕';
    }));
    result.grantReadText('Right', new TextReadCapability(['right'], key -> {
      seenRight.push(key);
      return 'R: jazz';
    }));
    return result;
  }

  public static function main():Void {
    var checker = new TypeChecker();
    checker.importSignature('readAsset', TextReadCapability.signature());
    ok(checker.signature('readAsset') == HostTextGrants.READ_SIGNATURE,
      'host ABI signature matches canonical type checker output');

    var left = encode('Left');
    var right = encode('Right');
    var decoded = ModuleImage.decode(left);
    ok(decoded.imports.length == 1 &&
      decoded.imports[0].module == HostTextGrants.PROVIDER &&
      decoded.imports[0].signature == HostTextGrants.READ_SIGNATURE,
      'portable image records an explicit host provider + exact signature');

    var seenLeft:Array<String> = [];
    var seenRight:Array<String> = [];
    var host = grants(seenLeft, seenRight);
    // A shared virtual provider is NOT a dependency that can be linked as
    // a compiled module. The same named grant is scoped by consumer module.
    var linked = ModuleLinker.linkImages([right, left], 40000000, host);
    ok(Vm.toPlain(linked.invoke('Left', 'lookup', Text('left'))) == 'L: 🪕',
      'left module reads its specifically granted text');
    ok(Vm.toPlain(linked.invoke('Right', 'lookup', Text('right'))) == 'R: jazz',
      'right module reads its separate grant');
    ok(Vm.toPlain(linked.invoke('Left', 'lookup', Text('right'))) == 'denied',
      'left cannot exercise right resource grant');
    ok(Vm.toPlain(linked.invoke('Right', 'lookup', Text('left'))) == 'denied',
      'right cannot exercise left resource grant');
    ok(Json.stringify(seenLeft) == '["left"]' &&
      Json.stringify(seenRight) == '["right"]',
      'denied keys never reach either host callback');

    fails(() -> ModuleLinker.linkImages([left]), 'missing host grants');
    fails(() -> ModuleLinker.linkImages([left], 40000000, new HostTextGrants()),
      'missing text reader grant');
    fails(() -> ModuleLinker.linkImages([left], 40000000,
      (function() {
        var other = new HostTextGrants();
        other.grantReadText('Right', new TextReadCapability(['left'], key -> 'wrong'));
        return other;
      })()), 'missing text reader grant');

    // A syntactically valid but forged canonical signature never controls
    // how a host function is typed by the linker.
    // A structurally wider record remains type-correct for the source,
    // but MUST NOT be accepted as the narrower host API contract.
    var wrongScheme:TypeScheme = {
      term:nail.NType.TFunction(nail.NType.TText,
        nail.NType.TStructural([
          {name:'error',type:nail.NType.TText},
          {name:'extra',type:nail.NType.TBoolean},
          {name:'ok',type:nail.NType.TBoolean},
          {name:'value',type:nail.NType.TText}
        ])),
      quantified:[], comparable:[]
    };
    fails(() -> ModuleLinker.linkImages([encode('BadType', 'readText', wrongScheme)],
      40000000, host), 'capability type mismatch');
    var unknown = encode('WrongSymbol', 'unknown');
    fails(() -> ModuleLinker.linkImages([unknown], 40000000, host),
      'missing function grant for WrongSymbol.unknown');

    fails(() -> host.grantReadText('Left', new TextReadCapability(['left'], key -> 'x')),
      'duplicate text reader');
    fails(() -> host.grantReadText('NailHost', new TextReadCapability(['left'], key -> 'x')),
      'invalid module');
    fails(() -> host.grantReadText('bad.path', new TextReadCapability(['left'], key -> 'x')),
      'invalid module');

    // Reject all counterfeit provider module images, whether produced through
    // the source compiler or by editing the portable JSON after compilation.
    fails(() -> ModuleLinker.compilePublic({
      name:'NailHost', source:'def readText key = key ;',
      imports:[], exports:['readText']
    }), 'reserved host provider name');
    var forged:Dynamic = Json.parse(left);
    Reflect.setField(forged, 'name', 'NailHost');
    fails(() -> ModuleImage.decode(Json.stringify(forged)),
      'reserved host provider name');

    // Normal module linking stays compatible; a dependency is not allowed
    // to import a host service merely because another module has it.
    var providerType = new TypeChecker();
    providerType.importSignature('readAsset', TextReadCapability.signature());
    providerType.check(source());
    var consumer:PublicSourceModuleSpec = {
      name:'Consumer', source:'def use key = foreign_lookup key ;',
      imports:[{module:'Left',symbol:'lookup',alias:'foreign_lookup',
        scheme:{term:nail.NType.TFunction(nail.NType.TText, nail.NType.TText),
          quantified:[],comparable:[]}}],
      exports:['use']
    };
    var consumerImage = ModuleImage.encode(ModuleLinker.compilePublic(consumer));
    var withDependent = ModuleLinker.linkImages([consumerImage, left], 40000000, host);
    ok(Vm.toPlain(withDependent.invoke('Consumer','use',Text('left'))) == 'L: 🪕',
      'dependent module can explicitly call provider public helper');
    fails(() -> ModuleLinker.linkImages([consumerImage, left], 40000000),
      'missing host grants');
    fails(() -> new TypeChecker().check(source()), 'readAsset');
    trace('NailSeed v0.38 explicit module host grants: ' + passed + ' checks passed');
  }
}
