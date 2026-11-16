import haxe.Timer;
import numeric.Rational;
import numeric.FastNumber;
import numeric.FastNumber.FastValue;
import numeric.NumericDialect;
import numeric.NumericDialect.NumericOutcome;
import numeric.NumericDialect.NumericSemantics;

class NumericFastTestMain {
  static var checks = 0;
  static var sink:Float = 0.0;

  static function ok(value:Bool, description:String):Void {
    if (!value) throw 'FAST-NUMERIC: ' + description;
    checks++;
  }

  static function equal(actual:String, expected:String, label:String):Void
    ok(actual == expected, label + ' expected ' + expected + ', got ' + actual);

  static function fails(f:Void->Void, expected:String):Void {
    var message = '';
    try f() catch (e:Dynamic) message = Std.string(e);
    ok(message.indexOf(expected) >= 0, 'expected "' + expected + '" got "' + message + '"');
  }

  static function canonical(value:FastValue):String return FastNumber.rational(value).toString();

  static function calculate(op:String, left:String, right:String):String
    return canonical(FastNumber.arithmetic(op, FastNumber.exact(left), FastNumber.exact(right)));

  static function original(op:String, left:String, right:String):String {
    var a = Rational.parse(left);
    var b = Rational.parse(right);
    return (switch (op) {
      case '+': a.add(b);
      case '-': a.subtract(b);
      case '*': a.multiply(b);
      case '/': a.divide(b);
      case _: throw 'invalid test operator';
    }).toString();
  }

  static function benchmark(label:String, iterations:Int, work:Void->Void):Void {
    var start = Timer.stamp();
    for (i in 0...iterations) work();
    trace('numeric-v029-benchmark ' + label + ' iterations=' + iterations
      + ' elapsed_ms=' + ((Timer.stamp() - start) * 1000));
  }

  public static function main():Void {
    // Fast path is checked only for signed integral values that fit 2^26.
    for (text in ['0', '-0', '+0', '7', '-7', '0007', '-0007', '67108864', '-67108864']) {
      if (text == '+0') {
        fails(() -> FastNumber.exact(text), 'Invalid');
        continue;
      }
      var value = FastNumber.exact(text);
      ok(switch (value) { case Small(_): true; case _: false; },
        'compact integer representation: ' + text);
      equal(canonical(value), Rational.parse(text).toString(), 'integer value');
      var wire = FastNumber.encodeExact(value);
      equal(FastNumber.encodeExact(FastNumber.decodeExact(wire)), wire,
        'canonical integer encoding');
    }

    for (text in ['67108865', '-67108865', '999999999999999999999',
      '1/3', '-7/2', '0.1', '1/67108864', '999999999999999999999/3']) {
      var value = FastNumber.exact(text);
      ok(switch (value) { case Fraction(_): true; case _: false; },
        'fraction or big integer representation: ' + text);
      equal(canonical(value), Rational.parse(text).toString(), 'fraction parity');
      var wire = FastNumber.encodeExact(value);
      equal(FastNumber.encodeExact(FastNumber.decodeExact(wire)), wire,
        'canonical fraction encoding');
    }

    equal(calculate('+', '67108864', '1'), '67108865', 'promote overflow');
    equal(calculate('-', '-67108864', '1'), '-67108865', 'promote negative overflow');
    equal(calculate('*', '67108864', '67108864'),
      '4503599627370496', 'exact 2^52 multiplication');
    equal(calculate('/', '6', '3'), '2', 'small exact quotient');
    equal(calculate('/', '1', '3'), '1/3', 'nonintegral quotient');
    equal(calculate('-', '2', '2'), '0', 'canonical zero');

    ok(FastNumber.equal(FastNumber.exact('2/4'), FastNumber.exact('1/2')),
      'fraction canonical equality');
    ok(FastNumber.compare(FastNumber.exact('-3'), FastNumber.exact('2')) < 0,
      'small ordering');
    ok(FastNumber.compare(FastNumber.exact('67108865'),
      FastNumber.exact('67108864')) > 0, 'mixed big/small ordering');
    ok(FastNumber.index(FastNumber.exact('2'), 3) == 2, 'small exact index');
    ok(FastNumber.index(FastNumber.exact('67108865'), 67108866) == 67108865,
      'big exact index within Haxe Int');
    fails(() -> FastNumber.index(FastNumber.exact('-1'), 10), 'integer in range');
    fails(() -> FastNumber.index(FastNumber.exact('1/2'), 10), 'integer in range');
    fails(() -> FastNumber.index(FastNumber.approximate(1.0), 10), 'Exact index required');

    fails(() -> FastNumber.decodeExact('F:3/1'), 'marker');
    fails(() -> FastNumber.decodeExact('E:03/1'), 'Noncanonical');
    fails(() -> FastNumber.decodeExact('E:3/2/1'), 'Invalid');
    fails(() -> FastNumber.encodeExact(FastNumber.approximate(3.0)),
      'Exact value required');
    fails(() -> FastNumber.arithmetic('+', FastNumber.exact('1'),
      FastNumber.approximate(0.2)), 'Explicit exact/Float');
    fails(() -> FastNumber.arithmetic('/', FastNumber.exact('1'),
      FastNumber.exact('0')), 'Division by zero');
    fails(() -> FastNumber.arithmetic('/', FastNumber.approximate(1.0),
      FastNumber.approximate(0.0)), 'Division by zero');
    fails(() -> FastNumber.approximate(Math.POSITIVE_INFINITY), 'Nonfinite');

    // Controlled property-style sampling, comparing the optimized and pure
    // rational paths across positive, zero, negative and promotion boundaries.
    var values = ['-67108865', '-67108864', '-123', '-7/3', '-1',
      '0', '1', '2', '5/7', '99', '67108864', '67108865', '0.125'];
    for (a in values) for (b in values) {
      for (op in ['+', '-', '*', '/']) {
        if (op == '/' && Rational.parse(b).numerator == '0') continue;
        equal(calculate(op, a, b), original(op, a, b),
          'optimized parity ' + a + ' ' + op + ' ' + b);
      }
    }

    // Keep work-limiting and conversion policies separate from precision.
    fails(() -> FastNumber.exact('12345', 3), 'digit budget exceeded');
    fails(() -> FastNumber.exact('1', 4097), 'Invalid exact numeric digit budget');
    fails(() -> FastNumber.arithmetic('*',
      FastNumber.exact('99999999', 9), FastNumber.exact('99999999', 9), 9),
      'digit budget exceeded');

    ok(NumericDialect.detect('def x = 1 ;') == LegacyFloat, 'legacy default');
    ok(NumericDialect.detect('# nail: 0.27\ndef x = 1 ;') == LegacyFloat,
      'explicit legacy dialect');
    ok(NumericDialect.detect('  \n # nail: 0.29\ndef x = 1 ;') == ExactNumber,
      'explicit exact dialect');
    ok(NumericDialect.detect('def x = 1 ;\n# nail: 0.29') == LegacyFloat,
      'header is not effective after source code');
    fails(() -> NumericDialect.detect('# nail: 0.28\n1 + 2 ;'),
      'Unsupported Nail source dialect 0.28');

    var legacy = NumericDialect.evaluate('0.1 + 0.2 ;', '0.1', '+', '0.2');
    var exact = NumericDialect.evaluate('# nail: 0.29\n0.1 + 0.2 ;',
      '0.1', '+', '0.2');
    ok(switch (legacy) { case Legacy(x): x != 0.3; case _: false; },
      'legacy Float addition remains approximate');
    ok(switch (exact) { case Exact(x): canonical(x) == '3/10'; case _: false; },
      'opt-in exact addition');
    equal(NumericDialect.describe(exact), 'exact:E:3/10', 'dialect result encoding');

    // Source-free, deterministic wire values: no intermediate JSON numbers.
    for (text in ['0','-1','1/3','999999999999999999999','-5/8']) {
      var encoded = FastNumber.encodeExact(FastNumber.exact(text));
      equal(encoded, FastNumber.encodeExact(FastNumber.decodeExact(encoded)),
        'binary-image-independent exact wire representation');
    }

    var smallA = FastNumber.exact('8');
    var smallB = FastNumber.exact('13');
    var ratA = Rational.parse('8');
    var ratB = Rational.parse('13');
    benchmark('fast-small-add', 12000, () -> {
      var result = FastNumber.arithmetic('+', smallA, smallB);
      switch (result) {
        case Small(n): sink += n;
        case _: throw 'expected integer fast path';
      }
    });
    benchmark('pure-rational-add', 12000, () -> {
      sink += ratA.add(ratB).numerator.length;
    });
    var floatA = Std.parseFloat('8');
    var floatB = Std.parseFloat('13');
    benchmark('float-add', 12000, () -> { sink += floatA + floatB; });
    ok(sink > 0, 'benchmarks computed real results');
    trace('NailSeed v0.29 compact numeric candidate: ' + checks + ' checks passed');
  }
}
