package numeric;

/** Source dialect selection shared by the host parser and both Nail compiler
    adapters. The obsolete standalone arithmetic evaluator lives in the
    historical numeric experiment tags, not in the active compiler. */
enum NumericSemantics {
  LegacyFloat;
  ExactNumber;
}

class NumericDialect {
  public static inline var LEGACY = '0.27';
  public static inline var EXACT = '0.29';

  public static function isExact(source:String):Bool return switch (detect(source)) {
    case ExactNumber: true;
    case LegacyFloat: false;
  };

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
}
