import haxe.Json;
import nail.BootRuntime;
import nail.BootstrapImage;
import nail.ByteVm;
import nail.BytecodeCompiler;
import nail.ExactImage;
import nail.TypeChecker;
import nail.Value;
import nail.Vm;
import numeric.FastNumber;

/** v0.43 exact arithmetic from an independent Nail source program. */
class ExactRoundingTestMain {
  static var passed = 0;

  static function ok(condition:Bool, label:String):Void {
    if (!condition) throw 'EXACT ROUNDING: ' + label;
    passed++;
  }

  static function same(actual:Array<Dynamic>, expected:Array<Dynamic>, label:String):Void {
    ok(Json.stringify(actual) == Json.stringify(expected),
      label + ' expected ' + Json.stringify(expected) +
      ', got ' + Json.stringify(actual));
  }

  static function fails(action:Void->Void, message:String):Void {
    var observed = '';
    try action() catch (error:Dynamic) observed = Std.string(error);
    ok(observed.indexOf(message) >= 0,
      'expected "' + message + '", got "' + observed + '"');
  }

  public static function main():Void {
    // A numerically exact rounding table, including negative values, zero
    // and half-even ties. Typechecker sees explicit Exact, not Float.
    var expressions = [
      'exactFloor ( 7 / 3 )',
      'exactFloor ( -7 / 3 )',
      'exactCeil ( 7 / 3 )',
      'exactCeil ( -7 / 3 )',
      'exactTruncate ( -7 / 3 )',
      'exactTruncate ( 7 / 3 )',
      'exactRoundEven ( 5 / 2 )',
      'exactRoundEven ( 7 / 2 )',
      'exactRoundEven ( -5 / 2 )',
      'exactRoundEven ( -7 / 2 )',
      'exactRoundEven ( 1 / 2 )',
      'exactRoundEven ( -1 / 2 )',
      'exactRoundEven ( -3 / 2 )',
      'exactFloor ( 0 / 7 )',
      'exactCeil ( -2 / 1 )',
      'exactIsInteger ( 8 / 2 )',
      'exactIsInteger ( 8 / 3 )',
      'exactIsInteger ( -8 / 2 )',
      'exactFloor ( 999999999999999999999999999999999999 / 3 )'
    ];
    var expected:Array<Dynamic> = [
      'E:2/1','E:-3/1','E:3/1','E:-2/1','E:-2/1','E:2/1',
      'E:2/1','E:4/1','E:-2/1','E:-4/1','E:0/1','E:0/1',
      'E:-2/1','E:0/1','E:-2/1',
      true,false,true,
      'E:333333333333333333333333333333333333/1'
    ];

    var source = '# nail: 0.29\n' +
      [for (expression in expressions) expression + ' ;'].join('\n');
    var vm = new Vm(40000000);
    vm.loadStdlib();
    same(new Vm(40000000).runPlain(source), expected,
      'AST interpreter evaluates all rounding modes');
    var reference = BytecodeCompiler.compileSource(source);
    same(new ByteVm(40000000).runPlain(reference), expected,
      'Haxe-compiled bytecode evaluates the same results');
    var selfCompiled = vm.compileWithNail(source);
    ok(BootstrapImage.encode(selfCompiled) == BootstrapImage.encode(reference),
      'Nail-written compiler agrees byte-for-byte with Haxe compiler');
    same(new ByteVm(40000000).runPlain(selfCompiled), expected,
      'Nail-compiled bytecode reproduces rounding results');
    var boot = new BootRuntime(40000000);
    var sourceFree = boot.compile(source);
    ok(BootstrapImage.encode(sourceFree) == BootstrapImage.encode(reference),
      'source-free compiler agrees byte-for-byte');
    same(boot.runBytecode(sourceFree).map(Vm.toPlain), expected,
      'source-free runtime executes rounding correctly');
    var wire = ExactImage.encode(sourceFree);
    ok(BootstrapImage.encode(ExactImage.decode(wire)) ==
      BootstrapImage.encode(reference), 'v2-exact module bytecode stays unchanged');

    var checker = new TypeChecker();
    var types = checker.preview(source);
    ok(types.length == expected.length, 'all expressions statically checked');
    for (i in 0...types.length)
      ok(types[i] == (i >= 15 && i < 18 ? 'Bool' : 'Exact'),
        'rounding returns Exact and predicate returns Bool at ' + i);
    var signatures = new TypeChecker();
    signatures.check('# nail: 0.29\ndef nearest n = exactRoundEven n ; '
      + 'def integral n = exactIsInteger n ;');
    ok(signatures.signature('nearest') == 'Exact -> Exact',
      'half-even can be used as an inferred unary function');
    ok(signatures.signature('integral') == 'Exact -> Bool',
      'integer predicate has a closed inferred type');

    // The 0.27 Float dialect remains binary floating point, without
    // silently coercing Float to Exact in either the checker or VM.
    fails(() -> new TypeChecker().check('exactFloor 1 ;'), 'cannot unify');
    fails(() -> new Vm().run('exactCeil 1 ;'), 'Expected exact number');
    same(new Vm().runPlain('0.1 + 0.2 ;'), [0.1 + 0.2],
      'legacy number arithmetic is unchanged');
    same(new Vm().runPlain('exactFloor ( exactFromText " 2.5 " ) ;'),
      ['E:2/1'], 'explicit exact conversion is available to legacy source');

    // No Float intermediate may occur in bigint rounding.
    var huge = '900719925474099300000000000000000000000000000002';
    var big = FastNumber.exact(huge + '/3');
    var rounded = FastNumber.roundInteger(big, 'floor');
    ok(FastNumber.encodeExact(rounded) ==
      'E:300239975158033100000000000000000000000000000000/1',
      'large exact integer rounding never loses high digits');
    ok(FastNumber.isInteger(rounded), 'rounded result is integer');
    fails(() -> FastNumber.roundInteger(FastNumber.exact('1/2'), 'random'),
      'Unknown exact integer rounding mode');
    fails(() -> FastNumber.roundInteger(
      FastNumber.approximate(0.5), 'floor'), 'Exact value required');
    fails(() -> FastNumber.roundInteger(
      FastNumber.exact('999/2'), 'ceil', 2),
      'Exact numeric digit budget exceeded');
    fails(() -> FastNumber.isInteger(FastNumber.approximate(1.0)),
      'Exact value required');

    trace('NailLang v0.43 exact rational rounding: ' + passed + ' tests passed');
  }
}
