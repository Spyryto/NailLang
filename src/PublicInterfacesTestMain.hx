import haxe.Json;
import nail.ModuleImage;
import nail.ModuleLinker;
import nail.ModuleLinker.InferredSourceModuleSpec;
import nail.ModuleLinker.PublicSourceModuleSpec;
import nail.TypeScheme;
import nail.NType;
import nail.TypeChecker;
import nail.Value;
import nail.Vm;

/** v0.33 first slice: infer public function signatures rather than repeat
    them in the host module manifest, while refusing nominal/generic ABIs. */
class PublicInterfacesTestMain {
  static var passed = 0;
  static function ok(value:Bool, reason:String):Void {
    if (!value) throw 'PUBLIC INTERFACE: ' + reason;
    passed++;
  }
  static function fails(f:Void->Void, needle:String):Void {
    var why = '';
    try f() catch (e:Dynamic) why = Std.string(e);
    ok(why.indexOf(needle) >= 0,
       'expected "' + needle + '", got "' + why + '"');
  }
  static function typeText(t:NType):String {
    var checker = new TypeChecker();
    checker.importSignature('signature', t);
    return checker.signature('signature');
  }

  public static function main():Void {
    var core:InferredSourceModuleSpec = {
      name:'Core',
      source:haxe.Resource.getString('interface_core'),
      imports:[],
      exports:['double']
    };
    var publicType = new TypeChecker();
    publicType.check(core.source);
    ok(typeText(publicType.closedPublicType('double')) == 'Number -> Number',
      'derive a closed source signature through existing type checker');
    fails(() -> publicType.closedPublicType('notThere'), 'unknown export notThere');
    fails(() -> publicType.closedPublicType('identity'), 'polymorphic export');

    var first = ModuleLinker.compileInferred(core);
    ok(first.exports.length == 1 && first.exports[0].name == 'double' &&
      first.exports[0].signature == 'Number -> Number',
      'derived public ABI includes only the named export');
    var client:InferredSourceModuleSpec = {
      name:'Client', source:haxe.Resource.getString('interface_client'),
      imports:[{module:'Core', symbol:'double',
        alias:'core_double', type:TFunction(TNumber, TNumber)}],
      exports:['run']
    };
    var second = ModuleLinker.compileInferred(client);
    var linked = ModuleLinker.linkImages([
      ModuleImage.encode(second), ModuleImage.encode(first)
    ]);
    ok(Vm.toPlain(linked.invoke('Client', 'run', Number(21))) == 43,
      'inferred independently compiled ABI links and executes');
    fails(() -> linked.read('Core', 'identity'), 'does not export identity');
    ok(linked.signature('Client', 'run') == 'Number -> Number',
      'consumer ABI is derived without duplicated export type');

    fails(() -> ModuleLinker.compileInferred({
      name:'Bad',source:core.source,imports:[],exports:['identity']
    }), 'polymorphic export');

    fails(() -> ModuleLinker.compileInferred({
      name:'Bad',source:core.source,imports:[],exports:['double', 'double']
    }), 'duplicate export');

    fails(() -> ModuleLinker.compileInferred({
      name:'Bad',source:core.source,imports:[],exports:['absent']
    }), 'unknown export absent');

    fails(() -> ModuleLinker.compileInferred({
      name:'ImportOnly',source:'def call n = external n ;',
      imports:[{module:'Core',symbol:'double',alias:'external',
        type:TFunction(TNumber,TNumber)}],exports:['external']
    }), 'export must be a local definition');

    var exact:InferredSourceModuleSpec = {
      name:'ExactCore',
      source:'# nail: 0.29\ndef double n = n * 2 ;',
      imports:[], exports:['double']
    };
    var exactImage = ModuleImage.encode(ModuleLinker.compileInferred(exact));
    ok(exactImage.indexOf('v2-exact') >= 0,
      'inferred ABI keeps opt-in exact bytecode envelope');
    var exactCompiled = ModuleLinker.linkImages([exactImage]);
    ok(Vm.toPlain(exactCompiled.invoke('ExactCore','double',
      ExactNumber(numeric.FastNumber.exact('21')))) == 'E:42/1',
      'inferred Exact -> Exact works without hidden approximation');

    var nominal = 'type Person { name String age Number } ;'
      + ' def age person = person . age ;';
    fails(() -> ModuleLinker.compileInferred({
      name:'Nominal',source:nominal,imports:[],exports:['age']
    }), 'nominal types require public type identity');


    // Second slice: independently compiled polymorphic interfaces with
    // alpha-invariant signatures and Eq constraints.
    var polySource = 'def identity x = x ; def same a b = a == b ;';
    var polyChecker = new TypeChecker();
    polyChecker.check(polySource);
    var identity = polyChecker.publicScheme('identity');
    var same = polyChecker.publicScheme('same');
    ok(polyChecker.signature('identity') == 'a -> a', 'public polymorphic identity');
    ok(polyChecker.signature('same') == 'Eq a => a -> a -> Bool', 'public Eq constraint');
    ok(identity.quantified.length == 1 && same.comparable.length == 1,
      'public schemes retain universal quantifiers and Eq evidence');

    var poly:PublicSourceModuleSpec = {
      name:'Polys', source:polySource, imports:[],
      exports:['identity', 'same']
    };
    var polyCompiled = ModuleLinker.compilePublic(poly);
    ok(polyCompiled.exports.length == 2 &&
      polyCompiled.exports[0].signature == 'a -> a' &&
      polyCompiled.exports[1].signature == 'Eq a => a -> a -> Bool',
      'full polymorphic signatures emitted in portable ABI');

    // A separate checker intentionally supplies alpha-renamed quantifier
    // IDs. Import IDs must not clash with builtins or each other.
    var renamed:TypeScheme = {
      term:TFunction(TVariable(700), TVariable(700)),
      quantified:[700], comparable:[]
    };
    var polyClient:PublicSourceModuleSpec = {
      name:'UsePolys',
      source:'def choose n = if foreign_same ( foreign_id n ) n then foreign_id true else false ;',
      imports:[
        {module:'Polys',symbol:'identity',alias:'foreign_id',scheme:renamed},
        {module:'Polys',symbol:'same',alias:'foreign_same',scheme:same}
      ],
      exports:['choose']
    };
    var clientCompiled = ModuleLinker.compilePublic(polyClient);
    var linkedPoly = ModuleLinker.linkImages([
      ModuleImage.encode(clientCompiled), ModuleImage.encode(polyCompiled)
    ]);
    ok(Vm.toPlain(linkedPoly.invoke('UsePolys', 'choose', Number(7))) == true,
      'linked identity works at Number and Bool in same client');
    ok(linkedPoly.signature('UsePolys', 'choose') == 'Eq a => a -> Bool',
      'consumer preserves imported equality polymorphism');
    ok(Vm.toPlain(linkedPoly.invoke('UsePolys', 'choose', Boolean(false))) == true,
      'the same consumer can also be invoked with Bool');

    var different = new TypeChecker();
    different.importPublicScheme('first', identity);
    different.importPublicScheme('second', renamed);
    different.check('def both n = first ( second n ) ;');
    ok(different.signature('both') == 'a -> a',
      'independent imported quantifiers do not collide');

    fails(() -> ModuleLinker.compilePublic({
      name:'Free',source:'def go x = imported x ;',
      imports:[{module:'Polys',symbol:'identity',alias:'imported',
        scheme:{term:TFunction(TVariable(42),TVariable(42)),
          quantified:[],comparable:[]}}],
      exports:['go']
    }), 'free type variable');
    fails(() -> different.importPublicScheme('badEq',
      {term:TVariable(1),quantified:[1],comparable:[2]}), 'invalid Eq constraint');
    fails(() -> different.importPublicScheme('badQuant',
      {term:TVariable(1),quantified:[1,1],comparable:[]}), 'duplicate');
    fails(() -> different.importPublicScheme('badNominal',
      {term:TRecord('Person'),quantified:[],comparable:[]}), 'nominal types');

    // Incorrectly weakening Eq constraints type-checks locally, but
    // cannot link to the provider that actually requires equality.
    var weakEq = ModuleLinker.compilePublic({
      name:'BadEq', source:'def choose n = foreign_same n n ;',
      imports:[{module:'Polys',symbol:'same',alias:'foreign_same',
        scheme:{term:TFunction(TVariable(1),
          TFunction(TVariable(1), TBoolean)),quantified:[1],comparable:[]}}],
      exports:['choose']
    });
    fails(() -> ModuleLinker.linkImages([
      ModuleImage.encode(polyCompiled), ModuleImage.encode(weakEq)
    ]), 'import type mismatch');

    fails(() -> ModuleLinker.compilePublic({
      name:'NotAnExport',source:polySource,imports:[],exports:['absent']
    }), 'export must be a local definition');

    // Third slice: opaque records with stable provider-qualified nominal
    // identities. The source-level constructor is intentionally qualified
    // until native module syntax can add a transparent local alias.
    var peopleSource = 'type People_Person { name Text age Number } ; '
      + 'def build n = People_Person " Ada " n ; '
      + 'def ageOf p = p . age ; '
      + 'def older p = ( p . age ) + 1 ;';
    var peopleChecker = new TypeChecker();
    peopleChecker.check(peopleSource);
    var buildScheme = peopleChecker.publicScheme('build', true);
    var ageScheme = peopleChecker.publicScheme('ageOf', true);
    ok(peopleChecker.signature('build') == 'Number -> People_Person',
      'record builder exposes its provider-qualified identity');
    ok(peopleChecker.signature('ageOf') == 'People_Person -> Number',
      'record accessor exposes a typed opaque public boundary');
    fails(() -> peopleChecker.publicScheme('build'),
      'nominal types require public type identity');

    var peopleModule:PublicSourceModuleSpec = {
      name:'People', source:peopleSource, imports:[],
      exports:['build', 'ageOf', 'People_Person']
    };
    var peopleCompiled = ModuleLinker.compilePublic(peopleModule);
    ok(peopleCompiled.exports.length == 3,
      'record constructor and helpers are exported by name');

    var consumer:PublicSourceModuleSpec = {
      name:'UsePeople',
      source:'def ageNext n = foreign_age ( foreign_build n ) + 1 ;',
      imports:[
        {module:'People',symbol:'build',alias:'foreign_build',scheme:buildScheme},
        {module:'People',symbol:'ageOf',alias:'foreign_age',scheme:ageScheme}
      ],
      exports:['ageNext']
    };
    var personConsumerCompiled = ModuleLinker.compilePublic(consumer);
    var peopleLinked = ModuleLinker.linkImages([
      ModuleImage.encode(personConsumerCompiled),
      ModuleImage.encode(peopleCompiled)
    ]);
    ok(Vm.toPlain(peopleLinked.invoke('UsePeople','ageNext',Number(38))) == 39,
      'opaque record crosses two independently compiled module boundaries');
    var tagged = peopleLinked.invoke('People','build',Number(31));
    ok(switch (tagged) {
      case Record(name, _): name == 'People_Person';
      case _: false;
    }, 'runtime record identity is the fully qualified nominal name');
    fails(() -> peopleLinked.read('People','older'),
      'does not export older');
    fails(() -> peopleLinked.read('UsePeople','foreign_build'),
      'does not export foreign_build');

    var calendarSource = 'type Calendar_Person { name Text age Number } ; '
      + 'def build n = Calendar_Person " Eve " n ; '
      + 'def ageOf p = p . age ;';
    var calendarChecker = new TypeChecker();
    calendarChecker.check(calendarSource);
    var calendarAge = calendarChecker.publicScheme('ageOf', true);
    var calendarCompiled = ModuleLinker.compilePublic({
      name:'Calendar',source:calendarSource,imports:[],
      exports:['build','ageOf']
    });
    ok(calendarCompiled.exports[0].signature == 'Number -> Calendar_Person',
      'same surface record shape in other module retains separate identity');
    fails(() -> ModuleLinker.compilePublic({
      name:'MixedNominal', source:'def wrong n = foreign_calendar_age ( foreign_build n ) ;',
      imports:[
        {module:'People',symbol:'build',alias:'foreign_build',scheme:buildScheme},
        {module:'Calendar',symbol:'ageOf',alias:'foreign_calendar_age',scheme:calendarAge}
      ],
      exports:['wrong']
    }), 'cannot unify Calendar_Person with People_Person');
    fails(() -> ModuleLinker.compilePublic({
      name:'Spoof', source:'type People_Person { age Number } ; '
        + 'def build n = People_Person n ;',
      imports:[],exports:['build']
    }), 'nominal record owner mismatch');
    fails(() -> ModuleLinker.compilePublic({
      name:'WrongOwner',source:'def invoke n = imported n ;',
      imports:[{module:'Calendar',symbol:'ageOf',alias:'imported',scheme:ageScheme}],
      exports:['invoke']
    }), 'imported nominal owner mismatch');
    fails(() -> ModuleLinker.compilePublic({
      name:'People_',source:'type People__Person { age Number } ; '
        + 'def build n = People__Person n ;',
      imports:[],exports:['build']
    }), 'nominal record owner mismatch');
    fails(() -> ModuleLinker.compilePublic({
      name:'UnderscoreSpoof',source:'type People__Person { age Number } ; '
        + 'def build n = People__Person n ;',
      imports:[],exports:['build']
    }), 'nominal record owner mismatch');
    fails(() -> ModuleLinker.compilePublic({
      name:'Unqualified', source:'type Person { age Number } ; '
        + 'def build n = Person n ;',
      imports:[],exports:['build']
    }), 'nominal record owner mismatch');
    fails(() -> ModuleLinker.compilePublic({
      name:'NoDirectFields',source:'def break p = p . age ;',
      imports:[{module:'People',symbol:'build',alias:'make',scheme:buildScheme}],
      exports:['break']
    }), 'unknown record field age');

    trace('NailSeed v0.33 public polymorphic and nominal interfaces: ' + passed
      + ' checks passed');
  }
}
