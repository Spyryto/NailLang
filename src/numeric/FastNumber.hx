package numeric;

/**
 * Experimental compact runtime representation for exact arithmetic.
 *
 * Small contains only signed integers in [-2^26, 2^26]. Native
 * integer arithmetic is used only when its result is guaranteed inside
 * this range; all larger products fall back before multiplication, avoiding
 * platform-specific overflow in the Haxe interpreter as well as JS and PHP.
 * All other exact values are canonical Rational objects. This does NOT
 * replace the core Nail Value.Number(Float) in the existing source dialect.
 */
enum FastValue {
  Small(value:Int);
  Fraction(value:Rational);
  Approximate(value:Float);
}

class FastNumber {
  public static inline var SMALL_LIMIT:Int = 67108864;
  public static inline var DEFAULT_DIGITS:Int = 128;
  public static inline var MAX_DIGITS:Int = 4096;

  // Diagnostic counters count paths, not actual JVM/JS/PHP heap allocations.
  // They are intended for comparing representative numeric workloads.
  public static var smallArithmetic(default, null):Int = 0;
  public static var rationalArithmetic(default, null):Int = 0;
  public static var smallToRational(default, null):Int = 0;

  public static function resetCounters():Void {
    smallArithmetic = 0;
    rationalArithmetic = 0;
    smallToRational = 0;
  }

  static function checkBudget(maxDigits:Int):Void {
    if (maxDigits < 1 || maxDigits > MAX_DIGITS)
      throw 'Invalid exact numeric digit budget';
  }

  static function limitInput(source:String, maxDigits:Int):Void {
    if (source == null || source.length < 1 ||
        source.length > maxDigits * 2 + 3)
      throw 'Exact numeric literal budget exceeded';
  }

  static function checkSize(r:Rational, budget:Int):Rational {
    if (r.numerator.length > budget || r.denominator.length > budget)
      throw 'Exact numeric digit budget exceeded';
    return r;
  }

  /** An intentionally conservative preflight cap, bounding expensive
      grade-school work before it starts. It can reject some operations
      that would later cancel to a tiny result. */
  static function preflight(op:String, a:Rational, b:Rational, budget:Int):Void {
    checkSize(a, budget);
    checkSize(b, budget);
    var numeratorCost = switch (op) {
      case '+' | '-':
        Std.int(Math.max(a.numerator.length + b.denominator.length,
          b.numerator.length + a.denominator.length)) + 1;
      case '*': a.numerator.length + b.numerator.length;
      case '/': a.numerator.length + b.denominator.length;
      case _: throw 'Unknown numeric operator ' + op;
    }
    var denominatorCost = switch (op) {
      case '+' | '-' | '*': a.denominator.length + b.denominator.length;
      case '/': a.denominator.length + b.numerator.length;
      case _: throw 'Unknown numeric operator ' + op;
    }
    // Inputs above the supported work budget are denied before constructing
    // the cross products, even if exact reduction would make a small result.
    if (numeratorCost > budget * 2 + 1 || denominatorCost > budget * 2 + 1)
      throw 'Exact numeric work budget exceeded';
  }

  static function smallFromCanonical(r:Rational):Null<Int> {
    if (r.denominator != '1' || r.numerator.length > 8) return null;
    var n = Std.parseInt(r.numerator);
    if (n == null || n > SMALL_LIMIT) return null;
    return r.negative ? -n : n;
  }

  public static function exact(token:String, maxDigits:Int = DEFAULT_DIGITS):FastValue {
    checkBudget(maxDigits);
    limitInput(token, maxDigits);
    // Direct lexical parsing avoids allocation, normalization, GCD and
    // BigNat for the most common safe-integer literals.
    var body = StringTools.startsWith(token, '-') ? token.substr(1) : token;
    if (body.length > 0 && body.length <= 8 && ~/^[0-9]+$/.match(body)) {
      var value = Std.parseInt(body);
      if (value != null && value <= SMALL_LIMIT) {
        if (maxDigits < 8 && Std.string(value).length > maxDigits)
          throw 'Exact numeric digit budget exceeded';
        return Small(StringTools.startsWith(token, '-') ? -value : value);
      }
    }
    var r = checkSize(Rational.parse(token), maxDigits);
    return fromRational(r);
  }

  public static function fromRational(r:Rational):FastValue {
    var n = smallFromCanonical(r);
    return n == null ? Fraction(r) : Small(n);
  }

  public static function approximate(value:Float):FastValue {
    if (!Math.isFinite(value)) throw 'Nonfinite approximate number';
    return Approximate(value);
  }

  public static function rational(value:FastValue):Rational return switch (value) {
    case Small(n):
      smallToRational++;
      Rational.parse(Std.string(n));
    case Fraction(r): r;
    case Approximate(_): throw 'Exact value required';
  };

  public static function arithmetic(op:String, a:FastValue, b:FastValue,
      maxDigits:Int = DEFAULT_DIGITS):FastValue {
    checkBudget(maxDigits);
    return switch ([a, b]) {
      case [Small(x), Small(y)]:
        // Haxe's eval target may preserve an Int runtime tag even when
        // assigning it to a Float local, so Float multiplication here is
        // NOT a portable way to avoid integer overflow. Never multiply
        // values unless the result is provably inside SMALL_LIMIT.
        var smallResult:Null<Int> = switch (op) {
          case '+':
            var v = x + y; // abs(v) <= 2^27, safe in a signed 32-bit Int
            v >= -SMALL_LIMIT && v <= SMALL_LIMIT ? v : null;
          case '-':
            var v = x - y; // abs(v) <= 2^27, safe in a signed 32-bit Int
            v >= -SMALL_LIMIT && v <= SMALL_LIMIT ? v : null;
          case '*':
            if (x == 0 || y == 0) 0
            else if (Math.abs(x) > SMALL_LIMIT / Math.abs(y)) null
            else x * y; // preflight guarantees abs(product) <= 2^26
          case '/':
            if (y == 0) throw 'Division by zero';
            x % y == 0 ? Std.int(x / y) : null;
          case _: throw 'Unknown numeric operator ' + op;
        };
        if (smallResult != null) {
          if (maxDigits < 8 &&
              Std.string(smallResult < 0 ? -smallResult : smallResult).length > maxDigits)
            throw 'Exact numeric digit budget exceeded';
          smallArithmetic++;
          Small(smallResult);
        } else {
          arithmeticExact(op, rational(a), rational(b), maxDigits);
        }
      case [Small(_), Fraction(_)] | [Fraction(_), Small(_)] |
           [Fraction(_), Fraction(_)]:
        arithmeticExact(op, rational(a), rational(b), maxDigits);
      case [Approximate(x), Approximate(y)]:
        if (op == '/' && y == 0) throw 'Division by zero';
        approximate(switch (op) {
          case '+': x + y;
          case '-': x - y;
          case '*': x * y;
          case '/': x / y;
          case _: throw 'Unknown numeric operator ' + op;
        });
      case _:
        throw 'Explicit exact/Float conversion required';
    };
  }

  static function arithmeticExact(op:String, x:Rational, y:Rational, budget:Int):FastValue {
    rationalArithmetic++;
    if (op == '/' && y.numerator == '0') throw 'Division by zero';
    preflight(op, x, y, budget);
    var result = switch (op) {
      case '+': x.add(y);
      case '-': x.subtract(y);
      case '*': x.multiply(y);
      case '/': x.divide(y);
      case _: throw 'Unknown numeric operator ' + op;
    };
    return fromRational(checkSize(result, budget));
  }

  /** Exact rounding to an integer, without ever converting through Float.
      For half-even (banker's rounding), ties select the even integer.
      The canonical Rational sign is separate and negative zero is impossible.
      All operations enforce the same output digit budget as exact arithmetic. */
  public static function roundInteger(value:FastValue, mode:String,
      maxDigits:Int = DEFAULT_DIGITS):FastValue {
    checkBudget(maxDigits);
    if (mode != 'floor' && mode != 'ceil' &&
        mode != 'truncate' && mode != 'half-even')
      throw 'Unknown exact integer rounding mode ' + mode;
    switch (value) {
      case Small(n):
        if (Std.string(n < 0 ? -n : n).length > maxDigits)
          throw 'Exact numeric digit budget exceeded';
        return value;
      case Approximate(_):
        throw 'Exact value required';
      case _:
    }
    var r = checkSize(rational(value), maxDigits);
    if (r.denominator == '1') return value;
    var qr = BigNat.divmod(r.numerator, r.denominator);
    var increase = switch (mode) {
      case 'floor': r.negative;
      case 'ceil': !r.negative;
      case 'truncate': false;
      case 'half-even':
        var doubled = BigNat.add(qr.r, qr.r);
        var comparison = BigNat.compare(doubled, r.denominator);
        comparison > 0 || (comparison == 0 &&
          (qr.q.charCodeAt(qr.q.length - 1) - 48) % 2 != 0);
      case _: false;
    };
    var whole = increase ? BigNat.add(qr.q, '1') : qr.q;
    if (whole.length > maxDigits)
      throw 'Exact numeric digit budget exceeded';
    return fromRational(Rational.make(r.negative, whole, '1'));
  }

  /** Exact integral predicate, including arbitrarily large integers. */
  public static function isInteger(value:FastValue):Bool return switch (value) {
    case Small(_): true;
    case Fraction(r): r.denominator == '1';
    case Approximate(_): throw 'Exact value required';
  };

  public static function equal(a:FastValue, b:FastValue):Bool {
    return switch ([a, b]) {
      case [Small(x), Small(y)]: x == y;
      case [Small(_), Fraction(_)] | [Fraction(_), Small(_)] |
           [Fraction(_), Fraction(_)]: rational(a).equals(rational(b));
      case [Approximate(x), Approximate(y)]: x == y;
      case _: throw 'Explicit exact/Float conversion required';
    };
  }

  public static function compare(a:FastValue, b:FastValue):Int {
    return switch ([a, b]) {
      case [Small(x), Small(y)]: x < y ? -1 : x > y ? 1 : 0;
      case [Small(_), Fraction(_)] | [Fraction(_), Small(_)] |
           [Fraction(_), Fraction(_)]: rational(a).compare(rational(b));
      case [Approximate(x), Approximate(y)]: x < y ? -1 : x > y ? 1 : 0;
      case _: throw 'Explicit exact/Float conversion required';
    };
  }

  public static function index(value:FastValue, size:Int):Int {
    if (size <= 0) throw 'Invalid indexed collection size';
    return switch (value) {
      case Small(n):
        if (n < 0 || n >= size) throw 'Exact array index must be an integer in range';
        n;
      case Fraction(r):
        if (r.negative || r.denominator != '1' ||
            BigNat.compare(r.numerator, Std.string(size)) >= 0)
          throw 'Exact array index must be an integer in range';
        // The comparison ensures the number fits Haxe's nonnegative Int range.
        Std.parseInt(r.numerator);
      case Approximate(_): throw 'Exact index required; convert explicitly';
    };
  }

  /** Canonical wire representation for exact values only.
      A denominator is always present: small 3 => E:3/1. */
  public static function encodeExact(value:FastValue):String {
    var r = rational(value);
    return 'E:' + (r.negative ? '-' : '') + r.numerator + '/' + r.denominator;
  }

  public static function decodeExact(data:String, maxDigits:Int = DEFAULT_DIGITS):FastValue {
    if (data == null || !StringTools.startsWith(data, 'E:'))
      throw 'Invalid exact numeric wire marker';
    var raw = data.substr(2);
    var value = exact(raw, maxDigits);
    if (encodeExact(value) != data)
      throw 'Noncanonical exact numeric wire value';
    return value;
  }

  public static function describe(value:FastValue):String return switch (value) {
    case Small(n): 'small:' + n;
    case Fraction(r): 'rational:' + r.toString();
    case Approximate(f): 'float:' + Std.string(f);
  };
}
