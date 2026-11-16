import haxe.Timer;
import numeric.Rational;
import numeric.NumericCandidate;
import numeric.NumericCandidate.NumericValue;

class NumericDecisionTestMain {
  static var checks = 0;
  static var sink = 0.0;

  static function ok(condition:Bool, name:String):Void {
    if (!condition) throw 'NUMERIC MODEL: ' + name;
    checks++;
  }

  static function fails(action:Void->Void, expected:String):Void {
    var message = '';
    try action() catch (e:Dynamic) message = Std.string(e);
    ok(message.indexOf(expected) >= 0, 'expected ' + expected + ', got ' + message);
  }

  static function exactString(value:NumericValue):String return switch (value) {
    case Exact(x): x.toString();
    case _: throw 'Expected exact candidate';
  };

  static function approximation(value:NumericValue):Float return switch (value) {
    case Approx(x): x;
    case _: throw 'Expected approximate candidate';
  };

  static function benchmark(name:String, iterations:Int, work:Void->Void):Void {
    var start = Timer.stamp();
    for (i in 0...iterations) work();
    var milliseconds = (Timer.stamp() - start) * 1000;
    trace('numeric-benchmark ' + name + ' iterations=' + iterations
      + ' elapsed_ms=' + milliseconds);
  }

  public static function main():Void {
    var oneThird = NumericCandidate.exact('1/3');
    var oneSixth = NumericCandidate.exact('1/6');
    ok(exactString(NumericCandidate.arithmetic('+', oneThird, oneSixth)) == '1/2',
      'exact fraction addition');
    ok(exactString(NumericCandidate.arithmetic('+',
      NumericCandidate.exact('0.1'), NumericCandidate.exact('0.2'))) == '3/10',
      'exact finite decimal addition');
    ok(NumericCandidate.equal(NumericCandidate.exact('6/8'),
      NumericCandidate.exact('3/4')), 'canonical exact equality');
    ok(NumericCandidate.compare(oneThird, oneSixth) > 0, 'exact comparison');
    ok(exactString(NumericCandidate.arithmetic('*',
      NumericCandidate.exact('-2/3'), NumericCandidate.exact('9/4'))) == '-3/2',
      'signed exact product');

    var approximateA = NumericCandidate.approximate(0.1);
    var approximateB = NumericCandidate.approximate(0.2);
    var sum = NumericCandidate.arithmetic('+', approximateA, approximateB);
    ok(approximation(sum) != 0.3, 'binary Float rounding is observable');
    ok(approximation(NumericCandidate.toApproximate(
      NumericCandidate.exact('1/2'))) == 0.5, 'explicit rational-to-Float conversion');
    fails(() -> NumericCandidate.arithmetic('+', oneThird, approximateA),
      'Explicit exact/Float conversion required');
    fails(() -> NumericCandidate.equal(oneThird, approximateA),
      'Explicit exact/Float conversion required');
    fails(() -> NumericCandidate.compare(oneThird, approximateA),
      'Explicit exact/Float conversion required');

    ok(NumericCandidate.index(NumericCandidate.exact('0'), 3) == 0,
      'zero index');
    ok(NumericCandidate.index(NumericCandidate.exact('2'), 3) == 2,
      'in-range integer index');
    fails(() -> NumericCandidate.index(NumericCandidate.exact('-1'), 3),
      'integer in range');
    fails(() -> NumericCandidate.index(NumericCandidate.exact('2/3'), 3),
      'integer in range');
    fails(() -> NumericCandidate.index(NumericCandidate.exact('3'), 3),
      'integer in range');
    fails(() -> NumericCandidate.index(NumericCandidate.exact('999999999999999'), 3),
      'integer in range');
    fails(() -> NumericCandidate.index(NumericCandidate.approximate(2.0), 3),
      'Exact index required');

    fails(() -> NumericCandidate.exact('1/1234567', 3), 'budget exceeded');
    fails(() -> NumericCandidate.exact('1/7', 0), 'Invalid exact numeric digit budget');
    fails(() -> NumericCandidate.arithmetic('*',
      NumericCandidate.exact('9999999', 8), NumericCandidate.exact('9999999', 8), 8),
      'budget exceeded');
    fails(() -> NumericCandidate.arithmetic('/', oneThird, NumericCandidate.exact('0')),
      'Division by zero');
    fails(() -> NumericCandidate.arithmetic('/', approximateA,
      NumericCandidate.approximate(0)), 'Division by zero');
    fails(() -> NumericCandidate.approximate(Math.NaN), 'Nonfinite');
    fails(() -> NumericCandidate.arithmetic('*',
      NumericCandidate.approximate(1e308), NumericCandidate.approximate(1e308)),
      'Nonfinite');
    var huge = NumericCandidate.exact('1' + StringTools.lpad('', '0', 350), 512);
    fails(() -> NumericCandidate.toApproximate(huge), 'cannot be converted');

    // Correctness and performance are separate. No arbitrary speed threshold:
    // interpreters, engines and deployment hardware vary considerably.
    var iterations = 1200;
    benchmark('exact/1/3+1/6', iterations, () -> {
      var result = NumericCandidate.arithmetic('+', oneThird, oneSixth);
      switch (result) {
        case Exact(x): sink += x.numerator.length;
        case _: throw 'Wrong numeric domain';
      }
    });
    var f1 = NumericCandidate.approximate(1 / 3);
    var f2 = NumericCandidate.approximate(1 / 6);
    benchmark('float/1/3+1/6', iterations, () -> {
      sink += approximation(NumericCandidate.arithmetic('+', f1, f2));
    });
    ok(sink > 0, 'benchmarks actually computed results');

    trace('NailSeed v0.28 numeric candidates: ' + checks + ' checks passed');
  }
}
