package numeric;

/** Only the current and semantically compatible language declarations are
    accepted; source versions do not select numeric modes or bytecode ABIs. */
class LanguageVersion {
  public static inline var CURRENT = '0.55';

  public static function supported(version:String):Bool return switch (version) {
    case '0.45' | '0.46' | '0.47' | '0.48' | '0.49' | '0.50' | '0.51' | '0.52' | '0.53' | '0.54' | CURRENT: true;
    case _: false;
  };

  public static function declared(source:String):Null<String> {
    if (source == null) throw 'Null Nail source';
    var tokens = nail.SourcePositions.scan(source);
    if (tokens.length == 0 || tokens[0].text != 'nail') return null;
    if (tokens.length < 3 || tokens[2].text != ';' ||
        !supported(tokens[1].text))
      throw 'Unsupported Nail language version (this VM supports 0.45 through '
        + CURRENT + ')';
    return tokens[1].text;
  }

  /** v0.49 relation declarations remain valid in 0.50 through 0.55.
      Pre-1.0 source/ABI compatibility is not otherwise guaranteed. */
  public static function hasGeneralRelations(version:Null<String>):Bool
    return version == '0.49' || version == '0.50' || version == '0.51' || version == '0.52' || version == '0.53' || version == '0.54' || version == CURRENT;

  public static function isModern(source:String):Bool
    return declared(source) != null;

  public static function hasArithmeticRelations(source:String):Bool
    return switch (declared(source)) {
      case '0.46' | '0.47' | '0.48' | '0.49' | '0.50' | '0.51'
        | '0.52' | '0.53' | '0.54' | CURRENT: true;
      case _: false;
    };
}
