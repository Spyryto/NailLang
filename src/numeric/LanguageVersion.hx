package numeric;

/** Language-version gate, independent from numeric types or VM bytecode ABI.
    v0.45 sources remain compatible with a v0.46 VM: their semantics did
    not change. v0.46 adds opt-in Add/Sub/Mul relations. */
class LanguageVersion {
  public static inline var CURRENT = '0.46';

  public static function declared(source:String):Null<String> {
    if (source == null) throw 'Null Nail source';
    var tokens = nail.SourcePositions.scan(source);
    if (tokens.length == 0 || tokens[0].text != 'nail') return null;
    if (tokens.length < 3 || tokens[2].text != ';' ||
        (tokens[1].text != '0.45' && tokens[1].text != CURRENT))
      throw 'Unsupported Nail language version (expected nail 0.45 ; or nail '
        + CURRENT + ' ;)';
    return tokens[1].text;
  }

  public static function isModern(source:String):Bool
    return declared(source) != null;

  public static function hasArithmeticRelations(source:String):Bool
    return declared(source) == CURRENT;
}
