package numeric;

/** Only the current and semantically compatible language declarations are
    accepted; source versions do not select numeric modes or bytecode ABIs. */
class LanguageVersion {
  public static inline var CURRENT = '0.47';

  public static function supported(version:String):Bool return switch (version) {
    case '0.45' | '0.46' | CURRENT: true;
    case _: false;
  };

  public static function declared(source:String):Null<String> {
    if (source == null) throw 'Null Nail source';
    var tokens = nail.SourcePositions.scan(source);
    if (tokens.length == 0 || tokens[0].text != 'nail') return null;
    if (tokens.length < 3 || tokens[2].text != ';' ||
        !supported(tokens[1].text))
      throw 'Unsupported Nail language version (this VM supports 0.45, 0.46 and '
        + CURRENT + ')';
    return tokens[1].text;
  }

  public static function isModern(source:String):Bool
    return declared(source) != null;

  public static function hasArithmeticRelations(source:String):Bool
    return switch (declared(source)) {
      case '0.46' | CURRENT: true;
      case _: false;
    };
}
