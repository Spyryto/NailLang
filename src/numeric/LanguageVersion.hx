package numeric;

/** Explicit source-language version, not a comment or numeric-mode switch.
    The compiler supports this new semantics as one complete unit.
    Legacy unversioned bootstrap sources still use their original parser. */
class LanguageVersion {
  public static inline var CURRENT = '0.45';

  public static function isModern(source:String):Bool {
    if (source == null) throw 'Null Nail source';
    var tokens = nail.SourcePositions.scan(source);
    if (tokens.length == 0 || tokens[0].text != 'nail') return false;
    if (tokens.length < 3 || tokens[1].text != CURRENT ||
        tokens[2].text != ';')
      throw 'Unsupported Nail language version (expected nail ' + CURRENT + ' ;)';
    return true;
  }
}
