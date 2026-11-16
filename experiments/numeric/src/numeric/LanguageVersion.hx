package numeric;

/** Provisional per-file dialect header. Independent of the Nail runtime.
 * A real release will validate this before passing source to the tokenizer.
 */
class LanguageVersion {
  public static final LEGACY = '0.15';
  public static final EXACT = '0.16';

  /** Header: '# nail: 0.16' as the first nonblank line.
   * When absent, preserve v0.15 legacy behavior.
   */
  public static function detect(source:String):String {
    var first = '';
    for (line in source.split('\n')) {
      var t = StringTools.trim(line);
      if (t != '') { first = t; break; }
    }
    if (!StringTools.startsWith(first, '# nail:')) return LEGACY;
    var version = StringTools.trim(first.substr('# nail:'.length));
    if (version != LEGACY && version != EXACT)
      throw 'Unsupported Nail language version: ' + version;
    return version;
  }
}
