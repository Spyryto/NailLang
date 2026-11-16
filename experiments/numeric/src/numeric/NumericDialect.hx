package numeric;

import numeric.FastNumber.FastValue;

/**
 * An explicit, *experimental* numeric source-dialect boundary.
 * The actual Nail compiler has not switched its VM, checker, or bytecode.
 * Version declarations are only effective in this adapter.
 */
enum NumericSemantics {
  LegacyFloat;
  ExactNumber;
}

enum NumericOutcome {
  Legacy(value:Float);
  Exact(value:FastValue);
}

class NumericDialect {
  public static inline var LEGACY = '0.27';
  public static inline var EXACT = '0.29';

  /** First nonempty line only; no undeclared semantic upgrades. */
  public static function detect(source:String):NumericSemantics {
    if (source == null) throw 'Null source';
    for (line in source.split('\n')) {
      var trimmed = StringTools.trim(line);
      if (trimmed.length == 0) continue;
      if (!StringTools.startsWith(trimmed, '# nail:')) return LegacyFloat;
      var header = StringTools.trim(trimmed.substr('# nail:'.length));
      return switch (header) {
        case LEGACY: LegacyFloat;
        case EXACT: ExactNumber;
        case _: throw 'Unsupported Nail source dialect ' + header;
      };
    }
    return LegacyFloat;
  }

  static function legacyLiteral(source:String):Float {
    // This adapter intentionally supports a documented subset of numeric
    // literal spellings. The core legacy parser remains the authority for
    // arbitrary source programs and is not called from here.
    if (source == null || !~/^-?[0-9]+(\.[0-9]+)?$/.match(source))
      throw 'Invalid legacy numeric literal ' + source;
    var number = Std.parseFloat(source);
    if (!Math.isFinite(number)) throw 'Nonfinite legacy numeric literal';
    return number;
  }

  /** Compare old and opted-in numeric operations without changing a global
      source-language meaning. Mixed-domain values never cross implicitly. */
  public static function evaluate(source:String, left:String, op:String, right:String,
      maxDigits:Int = FastNumber.DEFAULT_DIGITS):NumericOutcome {
    return switch (detect(source)) {
      case LegacyFloat:
        var a = legacyLiteral(left);
        var b = legacyLiteral(right);
        if (op == '/' && b == 0) throw 'Division by zero';
        var result = switch (op) {
          case '+': a + b;
          case '-': a - b;
          case '*': a * b;
          case '/': a / b;
          case _: throw 'Unknown numeric operator ' + op;
        };
        if (!Math.isFinite(result)) throw 'Nonfinite legacy arithmetic';
        Legacy(result);
      case ExactNumber:
        Exact(FastNumber.arithmetic(op,
          FastNumber.exact(left, maxDigits),
          FastNumber.exact(right, maxDigits), maxDigits));
    };
  }

  public static function describe(result:NumericOutcome):String return switch (result) {
    case Legacy(n): 'legacy-float:' + Std.string(n);
    case Exact(v): 'exact:' + FastNumber.encodeExact(v);
  };
}
