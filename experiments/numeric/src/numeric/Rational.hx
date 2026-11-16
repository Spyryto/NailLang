package numeric;

/** Immutable normalized arbitrary-precision rational with a positive denominator.
 * Sign separate from magnitude avoids platform-dependent signed integer behavior.
 */
class Rational {
  public var negative(default, null):Bool;
  public var numerator(default, null):String;
  public var denominator(default, null):String;

  private function new(negative:Bool, n:String, d:String) {
    this.negative = negative;
    this.numerator = n;
    this.denominator = d;
  }

  public static function make(negative:Bool, numerator:String, denominator:String):Rational {
    var n = BigNat.clean(numerator);
    var d = BigNat.clean(denominator);
    if (d == '0') throw 'Zero denominator';
    if (n == '0') return new Rational(false, '0', '1');
    var g = BigNat.gcd(n, d);
    return new Rational(negative, BigNat.divideExact(n, g), BigNat.divideExact(d, g));
  }

  /** Integers, fractions and decimal literals are all exact. */
  public static function parse(token:String):Rational {
    if (token == null || token == '') throw 'Empty numeric literal';
    var negative = StringTools.startsWith(token, '-');
    var s = negative ? token.substr(1) : token;
    if (s == '') throw 'Invalid numeric literal: ' + token;
    var slash = s.indexOf('/');
    var dot = s.indexOf('.');
    if (slash >= 0) {
      if (s.indexOf('/', slash + 1) >= 0 || dot >= 0) throw 'Invalid numeric literal: ' + token;
      return make(negative, s.substr(0, slash), s.substr(slash + 1));
    }
    if (dot >= 0) {
      if (s.indexOf('.', dot + 1) >= 0) throw 'Invalid numeric literal: ' + token;
      var before = s.substr(0, dot);
      var after = s.substr(dot + 1);
      if (before.length == 0 || after.length == 0) throw 'Invalid numeric literal: ' + token;
      var denominator = '1';
      for (i in 0...after.length) denominator += '0';
      return make(negative, before + after, denominator);
    }
    return make(negative, s, '1');
  }

  public function negate():Rational return make(!negative, numerator, denominator);

  public function add(other:Rational):Rational {
    var a = BigNat.multiply(numerator, other.denominator);
    var b = BigNat.multiply(other.numerator, denominator);
    var d = BigNat.multiply(denominator, other.denominator);
    if (negative == other.negative)
      return make(negative, BigNat.add(a, b), d);
    var c = BigNat.compare(a, b);
    if (c == 0) return make(false, '0', '1');
    return c > 0 ? make(negative, BigNat.subtract(a, b), d)
                 : make(other.negative, BigNat.subtract(b, a), d);
  }

  public function subtract(other:Rational):Rational return add(other.negate());

  public function multiply(other:Rational):Rational return make(
    negative != other.negative,
    BigNat.multiply(numerator, other.numerator),
    BigNat.multiply(denominator, other.denominator)
  );

  public function divide(other:Rational):Rational {
    if (other.numerator == '0') throw 'Division by zero';
    return make(negative != other.negative,
      BigNat.multiply(numerator, other.denominator),
      BigNat.multiply(denominator, other.numerator));
  }

  public function compare(other:Rational):Int {
    if (negative != other.negative) return negative ? -1 : 1;
    var result = BigNat.compare(BigNat.multiply(numerator, other.denominator),
                                BigNat.multiply(other.numerator, denominator));
    return negative ? -result : result;
  }

  public function equals(other:Rational):Bool return negative == other.negative
    && numerator == other.numerator && denominator == other.denominator;

  public function toString():String {
    return (negative ? '-' : '') + numerator + (denominator == '1' ? '' : '/' + denominator);
  }
}
