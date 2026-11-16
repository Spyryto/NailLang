import haxe.Timer;
import numeric.FastNumber;
import numeric.FastNumber.FastValue;
import numeric.Rational;

/** Reproducible, small real-world workloads: discounted line-item totals
    and beat positions in a musical tempo map. No host-specific heap API. */
class NumericWorkloadTestMain {
  static var checks = 0;
  static var guard:Float = 0;

  static function ok(value:Bool, label:String):Void {
    if (!value) throw 'NUMERIC WORKLOAD: ' + label;
    checks++;
  }

  static function repr(value:FastValue):String return FastNumber.rational(value).toString();

  static function invoiceFast(lines:Int):FastValue {
    var subtotal = FastNumber.exact('0');
    for (i in 0...lines) {
      var cents = FastNumber.exact(Std.string(1299 + i % 7));
      var quantity = FastNumber.exact(Std.string(1 + i % 4));
      var lineTotal = FastNumber.arithmetic('*', cents, quantity);
      subtotal = FastNumber.arithmetic('+', subtotal, lineTotal);
    }
    // Currency is kept exact in cents. Discount 5%, then add 22% VAT.
    return FastNumber.arithmetic('*',
      FastNumber.arithmetic('*', subtotal, FastNumber.exact('0.95')),
      FastNumber.exact('1.22'));
  }

  static function invoiceRational(lines:Int):Rational {
    var subtotal = Rational.parse('0');
    for (i in 0...lines) {
      var price = Rational.parse(Std.string(1299 + i % 7));
      var quantity = Rational.parse(Std.string(1 + i % 4));
      subtotal = subtotal.add(price.multiply(quantity));
    }
    return subtotal.multiply(Rational.parse('0.95')).multiply(Rational.parse('1.22'));
  }

  static function invoiceFloat(lines:Int):Float {
    var subtotal:Float = 0.0;
    for (i in 0...lines) subtotal += (1299 + i % 7) * (1 + i % 4);
    return subtotal * 0.95 * 1.22;
  }

  static function timelineFast(beats:Int):FastValue {
    var total = FastNumber.exact('0');
    var interval = FastNumber.exact('60/97'); // 97 BPM, exact seconds per beat
    for (i in 0...beats) total = FastNumber.arithmetic('+', total, interval);
    return total;
  }

  static function timelineRational(beats:Int):Rational {
    var total = Rational.parse('0');
    var interval = Rational.parse('60/97');
    for (i in 0...beats) total = total.add(interval);
    return total;
  }

  static function timelineFloat(beats:Int):Float {
    var total:Float = 0.0;
    var interval:Float = 60.0 / 97.0;
    for (i in 0...beats) total += interval;
    return total;
  }

  static function bench(label:String, runs:Int, action:Void->Void):Void {
    // Warm up each candidate before measuring; do not enforce timing ratios.
    for (i in 0...3) action();
    var start = Timer.stamp();
    for (i in 0...runs) action();
    trace('numeric-v029-workload ' + label + ' runs=' + runs
      + ' elapsed_ms=' + ((Timer.stamp() - start) * 1000));
  }

  public static function main():Void {
    var lines = 144;
    var beats = 128 * 4;

    FastNumber.resetCounters();
    var invoice = invoiceFast(lines);
    var reference = invoiceRational(lines);
    ok(repr(invoice) == reference.toString(),
      'discounted 144-line invoice is exactly identical to Rational baseline');
    ok(FastNumber.smallArithmetic == 2 * lines,
      'invoice ordinary integer multiplication/addition stays compact');
    ok(FastNumber.rationalArithmetic == 2,
      'invoice enters rational arithmetic only for discount and tax');
    ok(FastNumber.smallToRational == 1,
      'invoice materializes one small integer as Rational');
    trace('numeric-v029-invoice paths small=' + FastNumber.smallArithmetic
      + ' rational=' + FastNumber.rationalArithmetic
      + ' small-to-rational=' + FastNumber.smallToRational);

    FastNumber.resetCounters();
    var timeline = timelineFast(beats);
    ok(repr(timeline) == timelineRational(beats).toString(),
      '512-beat exact timeline equals Rational reference');
    ok(repr(timeline) == '30720/97',
      'four beats across 128 bars at 97 BPM retain exact position');
    ok(FastNumber.rationalArithmetic == beats,
      'fractional beat schedule uses rational fallback on each addition');
    trace('numeric-v029-timeline paths small=' + FastNumber.smallArithmetic
      + ' rational=' + FastNumber.rationalArithmetic
      + ' small-to-rational=' + FastNumber.smallToRational);

    var approximateInvoice = invoiceFloat(lines);
    var approximateTimeline = timelineFloat(beats);
    ok(Math.isFinite(approximateInvoice) && Math.isFinite(approximateTimeline),
      'approximate workflows return finite values');

    // Distinct workloads identify where a compact integer fast path helps:
    // invoices spend most time on integers; beat positions use fractions.
    bench('invoice/compact-exact', 15, () -> {
      guard += FastNumber.rational(invoiceFast(lines)).numerator.length;
    });
    bench('invoice/pure-rational', 15, () -> {
      guard += invoiceRational(lines).numerator.length;
    });
    bench('invoice/float', 15, () -> { guard += invoiceFloat(lines); });
    bench('tempo/compact-exact', 10, () -> {
      guard += FastNumber.rational(timelineFast(beats)).denominator.length;
    });
    bench('tempo/pure-rational', 10, () -> {
      guard += timelineRational(beats).denominator.length;
    });
    bench('tempo/float', 10, () -> { guard += timelineFloat(beats); });

    ok(guard > 0, 'all workload computations were used');
    trace('NailSeed v0.29 numeric workloads: ' + checks + ' checks passed');
  }
}
