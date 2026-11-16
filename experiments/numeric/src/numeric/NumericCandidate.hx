package numeric;

/** Two strictly separate candidate numeric domains.
    Exact rational arithmetic never silently falls into binary Float. */
enum NumericValue {
  Exact(value:Rational);
  Approx(value:Float);
}

/** An experimental semantics boundary, NOT yet part of Nail's VM.
    Resource limits bound the pure-Haxe decimal-digit rational implementation. */
class NumericCandidate {
  public static inline var DEFAULT_DIGITS = 128;
  public static inline var MAX_DIGITS = 4096;

  static function budget(maxDigits:Int):Void {
    if (maxDigits < 1 || maxDigits > MAX_DIGITS)
      throw 'Invalid exact numeric digit budget';
  }

  static function bounded(value:Rational, maxDigits:Int):Rational {
    if (value.numerator.length > maxDigits || value.denominator.length > maxDigits)
      throw 'Exact numeric digit budget exceeded';
    return value;
  }

  public static function exact(token:String, maxDigits:Int = DEFAULT_DIGITS):NumericValue {
    budget(maxDigits);
    if (token == null || token.length > maxDigits * 2 + 3)
      throw 'Exact numeric literal budget exceeded';
    return Exact(bounded(Rational.parse(token), maxDigits));
  }

  public static function approximate(value:Float):NumericValue {
    if (!Math.isFinite(value)) throw 'Nonfinite approximate number';
    return Approx(value);
  }

  public static function arithmetic(op:String, a:NumericValue, b:NumericValue,
      maxDigits:Int = DEFAULT_DIGITS):NumericValue {
    budget(maxDigits);
    return switch ([a, b]) {
      case [Exact(x), Exact(y)]:
        bounded(x, maxDigits);
        bounded(y, maxDigits);
        Exact(bounded(switch (op) {
          case '+': x.add(y);
          case '-': x.subtract(y);
          case '*': x.multiply(y);
          case '/': x.divide(y);
          case _: throw 'Unknown numeric operator ' + op;
        }, maxDigits));
      case [Approx(x), Approx(y)]:
        if (op == '/' && y == 0) throw 'Division by zero';
        approximate(switch (op) {
          case '+': x + y;
          case '-': x - y;
          case '*': x * y;
          case '/': x / y;
          case _: throw 'Unknown numeric operator ' + op;
        });
      case _: throw 'Explicit exact/Float conversion required';
    };
  }

  public static function compare(a:NumericValue, b:NumericValue):Int {
    return switch ([a, b]) {
      case [Exact(x), Exact(y)]: x.compare(y);
      case [Approx(x), Approx(y)]: x < y ? -1 : x > y ? 1 : 0;
      case _: throw 'Explicit exact/Float conversion required';
    };
  }

  public static function equal(a:NumericValue, b:NumericValue):Bool {
    return switch ([a, b]) {
      case [Exact(x), Exact(y)]: x.equals(y);
      case [Approx(x), Approx(y)]: x == y;
      case _: throw 'Explicit exact/Float conversion required';
    };
  }

  /** Conservative explicit conversion; if magnitudes cannot individually
      be represented as finite floats, reject even if their ratio is finite. */
  public static function toApproximate(value:NumericValue):NumericValue {
    return switch (value) {
      case Approx(_): value;
      case Exact(x):
        var numerator = Std.parseFloat(x.numerator);
        var denominator = Std.parseFloat(x.denominator);
        if (!Math.isFinite(numerator) || !Math.isFinite(denominator))
          throw 'Exact value cannot be converted by the bounded Float bridge';
        approximate((x.negative ? -numerator : numerator) / denominator);
    };
  }

  /** Existing Nail index behavior can be preserved without truncating exact
      numbers or allowing approximate values to index arrays silently. */
  public static function index(value:NumericValue, size:Int):Int {
    if (size < 1) throw 'Invalid indexed collection size';
    return switch (value) {
      case Exact(x):
        if (x.negative || x.denominator != '1' ||
            BigNat.compare(x.numerator, Std.string(size)) >= 0)
          throw 'Exact array index must be an integer in range';
        Std.parseInt(x.numerator);
      case Approx(_): throw 'Exact index required; convert explicitly';
    };
  }

  public static function describe(value:NumericValue):String {
    return switch (value) {
      case Exact(x): 'exact:' + x.toString();
      case Approx(x): 'float:' + Std.string(x);
    };
  }
}
