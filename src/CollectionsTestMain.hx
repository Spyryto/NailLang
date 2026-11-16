import haxe.Json;
import haxe.Resource;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.TypeChecker;
import nail.Vm;

/**
 * Persistent Map/Set library implemented with pre-existing Nail values.
 * The library is tested through both compilers and three runtime paths.
 */
class CollectionsTestMain {
  static var passed = 0;

  static function ok(condition:Bool, label:String):Void {
    if (!condition) throw 'COLLECTIONS: ' + label;
    passed++;
  }

  static function fails(f:Void->Void, expected:String):Void {
    var message = '';
    try f() catch (e:Dynamic) message = Std.string(e);
    ok(message.indexOf(expected) >= 0,
      'expected "' + expected + '"; got "' + message + '"');
  }

  /** Read precisely the deployed Nail definitions, not a copied test fixture. */
  static function collectionSource():String {
    var stdlib = Resource.getString('stdlib');
    if (stdlib == null) throw 'Missing standard library resource';
    var begin = '# v0.37 collections BEGIN';
    var end = '# v0.37 collections END';
    var start = stdlib.indexOf(begin);
    var stop = stdlib.indexOf(end, start);
    if (start < 0 || stop < 0) throw 'Missing collections source markers';
    return stdlib.substring(start, stop + end.length) + '\n';
  }

  static function same(source:String, expected:String):Void {
    var code = collectionSource() + '\n' + source;
    // Semantic typing is checked independently of each evaluator.
    new TypeChecker().check(code);
    passed++;

    var reference = BytecodeCompiler.compileSource(code);
    var image = BootstrapImage.encode(reference);
    var self = new Vm(70000000);
    self.loadStdlib();
    ok(image == BootstrapImage.encode(self.compileWithNail(code)),
      'Haxe and Nail compilers produce identical bytecode');
    ok(Json.stringify(new Vm(70000000).runPlain(code)) == expected,
      'host AST VM collection result');
    ok(Json.stringify(new ByteVm(70000000).runPlain(reference)) == expected,
      'bytecode VM collection result');
    // The two following paths use the deployed stdlib, with no duplicate defs.
    ok(Json.stringify(self.runPlainWithNail(source)) == expected,
      'Nail self-parser collection result');
    ok(Json.stringify(new BootRuntime(70000000).runPlain(source)) == expected,
      'source-free bootstrap collection result');
    ok(image == BootstrapImage.encode(BootstrapImage.decode(image)),
      'portable image roundtrip');
  }

  public static function main():Void {
    var library = collectionSource();
    var checker = new TypeChecker();
    checker.check(library);
    ok(checker.signature('mapPut').indexOf('MapEntry[') >= 0,
      'mapPut uses a generic nominal entry');
    ok(checker.signature('mapFind').indexOf('MapLookup[') >= 0,
      'mapFind returns a typed lookup result');
    ok(checker.signature('setAdd').indexOf('[') >= 0,
      'setAdd is generic over immutable lists');

    // Small practical program: update a set list of BPMs without duplicates.
    same('def bpm = mapPut ( mapPut mapEmpty " Blue " 116 ) " Green " 120 ; '
      + 'def edited = mapPut bpm " Blue " 132 ; '
      + 'def after = mapDelete edited " Green " ; '
      + 'def orZero result = match result with '
      + '| MapMissing -> 0 | MapFound value -> value ; '
      + 'orZero ( mapFind after " Blue " ) ; '
      + 'mapContains after " Blue " ; '
      + 'mapContains after " Green " ; '
      + 'orZero ( mapFind after " Green " ) ;',
      '[132,true,false,0]');

    // Replacement and deletion remove duplicates, including raw-list inputs.
    same('def raw = [ MapEntry " same " 1 , MapEntry " same " 2 ] ; '
      + 'def replaced = mapPut raw " same " 3 ; '
      + 'def without = mapDelete raw " same " ; '
      + 'def orZero result = match result with '
      + '| MapMissing -> 0 | MapFound value -> value ; '
      + 'orZero ( mapFind replaced " same " ) ; '
      + 'mapContains without " same " ; '
      + 'mapContains replaced " absent " ;',
      '[3,false,false]');

    // A generic key need only support equality; values may have other types.
    same('def flags = mapPut ( mapPut mapEmpty true " Ready " ) '
      + 'false " Pause " ; '
      + 'def read result = match result with '
      + '| MapMissing -> " none " | MapFound value -> value ; '
      + 'read ( mapFind flags false ) ; '
      + 'read ( mapFind flags true ) ;',
      '["Pause","Ready"]');

    // Set idempotence, removal and non-ASCII Text keys.
    same('def names = setAdd ( setAdd ( setAdd setEmpty " bossa " ) '
      + '" gypsy " ) " bossa " ; '
      + 'setContains names " bossa " ; '
      + 'setContains ( setDelete names " bossa " ) " bossa " ; '
      + 'setContains names " gypsy " ; '
      + 'setContains ( setAdd setEmpty true ) true ; '
      + 'setContains ( setAdd setEmpty " 🪕 " ) " 🪕 " ;',
      '[true,false,true,true,true]');

    // The type checker prevents heterogeneous key/value sets and function keys.
    fails(() -> new TypeChecker().check(library
      + 'mapPut ( mapPut mapEmpty " x " 1 ) true 2 ;'),
      'cannot unify');
    fails(() -> new TypeChecker().check(library
      + 'mapPut ( mapPut mapEmpty " x " 1 ) " y " false ;'),
      'cannot unify');
    fails(() -> new TypeChecker().check(library
      + 'setAdd ( setAdd setEmpty true ) " x " ;'),
      'cannot unify');
    fails(() -> new TypeChecker().check(library
      + 'setContains [ fun x -> x ] ( fun y -> y ) ;'),
      'functions cannot be compared');

    trace('NailSeed v0.37 persistent collections: ' + passed + ' checks passed');
  }
}
