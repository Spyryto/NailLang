import haxe.Json;
import nail.BootstrapImage;
import nail.BytecodeCompiler;
import nail.ModuleImage;
import nail.ModuleImage.CompiledModule;
import nail.ModuleLinker;
import nail.ModuleLinker.SourceModuleSpec;
import nail.NType;
import nail.Value;
import nail.Vm;
import numeric.FastNumber;

class RuntimeModulesTestMain {
  static var passed = 0;

  static function ok(condition:Bool, label:String):Void {
    if (!condition) throw 'RUNTIME MODULES: ' + label;
    passed++;
  }

  static function fails(action:Void->Void, needle:String):Void {
    var message = '';
    try action() catch (e:Dynamic) message = Std.string(e);
    ok(message.indexOf(needle) >= 0,
      'expected "' + needle + '", got "' + message + '"');
  }

  static function fn(a:NType):NType return TFunction(a, a);

  static function normalModules():Array<SourceModuleSpec> {
    return [
      {
        name:'Core',
        source:haxe.Resource.getString('module_core'),
        imports:[],
        exports:[{name:'double', type:fn(TNumber)}]
      },
      {
        name:'Math',
        source:haxe.Resource.getString('module_math'),
        imports:[{module:'Core', symbol:'double',
          alias:'core_double', type:fn(TNumber)}],
        exports:[{name:'triple', type:fn(TNumber)}]
      },
      {
        name:'Application',
        source:haxe.Resource.getString('module_app'),
        imports:[{module:'Math', symbol:'triple',
          alias:'math_triple', type:fn(TNumber)}],
        exports:[{name:'compute', type:fn(TNumber)}]
      }
    ];
  }

  static function exactModules():Array<SourceModuleSpec> {
    return [
      {
        name:'ExactMath',
        source:'# nail: 0.29\ndef double n = n * 2 ;',
        imports:[],
        exports:[{name:'double', type:fn(TExact)}]
      },
      {
        name:'ExactApplication',
        source:'# nail: 0.29\ndef compute n = imported_double n ;',
        imports:[{module:'ExactMath', symbol:'double',
          alias:'imported_double', type:fn(TExact)}],
        exports:[{name:'compute', type:fn(TExact)}]
      }
    ];
  }

  static function musicalModules():Array<SourceModuleSpec> {
    return [
      {
        name:'Tempo',
        source:haxe.Resource.getString('module_tempo'),
        imports:[],
        exports:[{name:'secondsPerBeat',type:fn(TExact)}]
      },
      {
        name:'Phrase',
        source:haxe.Resource.getString('module_phrase'),
        imports:[{module:'Tempo',symbol:'secondsPerBeat',
          alias:'tempo_secondsPerBeat',type:fn(TExact)}],
        exports:[{name:'phraseSeconds',type:fn(TExact)}]
      }
    ];
  }

  public static function main():Void {
    var sources = normalModules();
    var images:Array<String> = [];
    for (spec in sources) {
      var compiled = ModuleLinker.compile(spec);
      var encoded = ModuleImage.encode(compiled);
      var decoded = ModuleImage.decode(encoded);
      ok(decoded.name == spec.name && decoded.dialect == '0.27',
        'module interface round trips without source: ' + spec.name);
      ok(BootstrapImage.encode(compiled.code) == BootstrapImage.encode(decoded.code),
        'module bytecode is lossless: ' + spec.name);
      ok(encoded.length > 100 && encoded.indexOf('runtime-module.v1') >= 0,
        'independent module image has explicit format');
      images.push(encoded);
    }

    // The source compiler is finished: no source strings are supplied to the
    // linker, and the units may be linked in an arbitrary input order.
    var linked = ModuleLinker.linkImages([images[2], images[0], images[1]]);
    ok(Vm.toPlain(linked.invoke('Application', 'compute', Number(14))) == 42,
      'three independently compiled modules share only public aliases');
    ok(Vm.toPlain(linked.invoke('Core', 'double', Number(6))) == 12,
      'public function can be invoked directly');
    ok(linked.signature('Math', 'triple') == 'Number -> Number',
      'module image retains inferred and declared type signature');
    fails(() -> linked.read('Core', 'hidden'), 'does not export hidden');
    fails(() -> linked.read('Application', 'core_double'),
      'does not export core_double');
    fails(() -> linked.invoke('Math', 'hidden', Number(5)), 'does not export hidden');
    fails(() -> linked.read('Missing', 'double'), 'unknown module Missing');

    var cloned = ModuleLinker.linkImages(images);
    ok(Vm.toPlain(cloned.invoke('Application', 'compute', Number(5))) == 15,
      'independent linking initializes new module environment');

    var exactSpecs = exactModules();
    var exactImages = [for (s in exactSpecs)
      ModuleImage.encode(ModuleLinker.compile(s))];
    var exactDecoded = ModuleImage.decode(exactImages[0]);
    ok(exactDecoded.dialect == '0.29' &&
      exactImages[0].indexOf('postfix-image.v2-exact') >= 0,
      'exact module uses isolated version-2 exact bytecode envelope');
    var exactLinked = ModuleLinker.linkImages(exactImages);
    var returned = Vm.toPlain(exactLinked.invoke(
      'ExactApplication', 'compute', ExactNumber(FastNumber.exact('21'))));
    ok(returned == 'E:42/1',
      'separately compiled exact modules preserve exact arithmetic');

    // A real exact-number application: 128 bars of 4 beats at 97 BPM.
    // This is a rational number of seconds, never rounded to binary Float.
    var musicArtifacts = [for (spec in musicalModules())
      ModuleImage.encode(ModuleLinker.compile(spec))];
    var music = ModuleLinker.linkImages(musicArtifacts);
    var seconds = Vm.toPlain(music.invoke('Phrase', 'phraseSeconds',
      ExactNumber(FastNumber.exact('128'))));
    ok(seconds == 'E:30720/97',
      'two separately compiled music modules preserve exact beat positions');
    ok(music.signature('Tempo', 'secondsPerBeat') == 'Exact -> Exact',
      'exact timing module publishes its typed interface');
    fails(() -> music.read('Phrase', 'tempo_secondsPerBeat'),
      'does not export tempo_secondsPerBeat');

    var mistyped:SourceModuleSpec = {
      name:'BadType', source:'def double n = n * 2 ;',
      imports:[], exports:[{name:'double',type:TFunction(TNumber,TBoolean)}]
    };
    fails(() -> ModuleLinker.compile(mistyped), 'export type mismatch');

    var missingExport:SourceModuleSpec = {
      name:'MissingExport', source:'def one = 1 ;',
      imports:[], exports:[{name:'phantom',type:TNumber}]
    };
    fails(() -> ModuleLinker.compile(missingExport),
      'export must be a local definition');

    var expression:SourceModuleSpec = {
      name:'Expression', source:'1 + 2 ;',
      imports:[], exports:[]
    };
    fails(() -> ModuleLinker.compile(expression),
      'top-level expressions are not permitted');

    var unknown:SourceModuleSpec = {
      name:'Unknown', source:'def steal n = hidden n ;',
      imports:[], exports:[{name:'steal',type:fn(TNumber)}]
    };
    fails(() -> ModuleLinker.compile(unknown), 'unknown name hidden');

    var shadow:SourceModuleSpec = {
      name:'Shadow', source:'def core_double n = n ;',
      imports:[{module:'Core',symbol:'double',alias:'core_double',
        type:fn(TNumber)}],
      exports:[{name:'core_double',type:fn(TNumber)}]
    };
    fails(() -> ModuleLinker.compile(shadow),
      'shadows imported alias');

    var invalidAlias:SourceModuleSpec = {
      name:'InvalidAlias', source:'def f n = head n ;',
      imports:[{module:'Core',symbol:'double',alias:'head',
        type:fn(TNumber)}],
      exports:[{name:'f',type:fn(TNumber)}]
    };
    fails(() -> ModuleLinker.compile(invalidAlias),
      'duplicate or reserved import alias');

    var duplicateImport:SourceModuleSpec = {
      name:'DuplicateImport', source:'def f n = item n ;',
      imports:[
        {module:'Core',symbol:'double',alias:'item',type:fn(TNumber)},
        {module:'Math',symbol:'triple',alias:'item',type:fn(TNumber)}
      ],
      exports:[{name:'f',type:fn(TNumber)}]
    };
    fails(() -> ModuleLinker.compile(duplicateImport), 'duplicate import alias');

    var privateImport:SourceModuleSpec = {
      name:'Privacy', source:'def stolen n = stolen_private n ;',
      imports:[{module:'Core',symbol:'hidden',alias:'stolen_private',
        type:fn(TNumber)}],
      exports:[{name:'stolen',type:fn(TNumber)}]
    };
    var privateArtifact = ModuleImage.encode(ModuleLinker.compile(privateImport));
    fails(() -> ModuleLinker.linkImages([privateArtifact, images[0]]),
      'does not export hidden');

    var wrongContract:SourceModuleSpec = {
      name:'WrongContract', source:'def compute n = wrong_double n ;',
      imports:[{module:'Core',symbol:'double',alias:'wrong_double',
        type:fn(TExact)}],
      exports:[{name:'compute',type:fn(TExact)}]
    };
    var wrongArtifact = ModuleImage.encode(ModuleLinker.compile(wrongContract));
    fails(() -> ModuleLinker.linkImages([wrongArtifact, images[0]]),
      'import type mismatch');

    var crossDialect:SourceModuleSpec = {
      name:'CrossDialect',
      source:'# nail: 0.29\ndef compute n = wrong_double n ;',
      imports:[{module:'Core',symbol:'double',alias:'wrong_double',
        type:fn(TExact)}],
      exports:[{name:'compute',type:fn(TExact)}]
    };
    var crossArtifact = ModuleImage.encode(ModuleLinker.compile(crossDialect));
    fails(() -> ModuleLinker.linkImages([crossArtifact, images[0]]),
      'incompatible numeric dialect');

    fails(() -> ModuleLinker.linkImages([images[1]]),
      'missing dependency Core');
    fails(() -> ModuleLinker.linkImages([images[0], images[0]]),
      'duplicate module Core');

    var cycleA:SourceModuleSpec = {
      name:'CycleA',
      source:'def run n = imported_b n ;',
      imports:[{module:'CycleB',symbol:'run',alias:'imported_b',
        type:fn(TNumber)}],
      exports:[{name:'run',type:fn(TNumber)}]
    };
    var cycleB:SourceModuleSpec = {
      name:'CycleB',
      source:'def run n = imported_a n ;',
      imports:[{module:'CycleA',symbol:'run',alias:'imported_a',
        type:fn(TNumber)}],
      exports:[{name:'run',type:fn(TNumber)}]
    };
    var cycles = [ModuleImage.encode(ModuleLinker.compile(cycleA)),
      ModuleImage.encode(ModuleLinker.compile(cycleB))];
    fails(() -> ModuleLinker.linkImages(cycles), 'cyclic imports');

    var badFormat:Dynamic = Json.parse(images[0]);
    Reflect.setField(badFormat, 'format', 'nailseed.runtime-module.v0');
    fails(() -> ModuleImage.decode(Json.stringify(badFormat)),
      'incompatible format');

    var brokenDialect:Dynamic = Json.parse(images[0]);
    Reflect.setField(brokenDialect, 'dialect', '0.29');
    fails(() -> ModuleImage.decode(Json.stringify(brokenDialect)),
      'exact image');

    var badInterface:Dynamic = Json.parse(images[0]);
    var exposed:Array<Dynamic> = cast Reflect.field(badInterface, 'exports');
    exposed.push(exposed[0]);
    fails(() -> ModuleImage.decode(Json.stringify(badInterface)),
      'duplicate export double');

    var malformed:CompiledModule = {
      name:'Malformed', dialect:'0.27', imports:[], exports:[],
      code:BytecodeCompiler.compileSource('1 ;')
    };
    fails(() -> ModuleLinker.link([malformed]),
      'only local definitions are allowed');

    trace('NailSeed v0.31 runtime module integration: ' + passed + ' checks passed');
  }
}
