package nail;

import haxe.iterators.StringIteratorUnicode;

/** Portable Unicode scalar indexing for Nail Text.
    String.length/charAt count different units on JS, PHP and the Haxe
    interpreter. Nail's textLength and textAt count Unicode codepoints
    (not UTF-8 bytes, UTF-16 code units, or grapheme clusters).

    The Nail-written tokenizer indexes the same source at every position.
    Cache at most four immutable strings so its textAt is amortized O(1)
    instead of performing a quadratic Unicode scan during self-bootstrap.
    There is no observable state in the Nail language. */
private typedef UnicodeEntry = {
  final source:String;
  final scalars:Array<Int>;
}

class UnicodeText {
  static final MAX_ENTRIES = 4;
  static final MAX_CACHED_SCALARS = 262144;
  static var recent:Array<UnicodeEntry> = [];

  static function points(source:String):Array<Int> {
    for (i in 0...recent.length) {
      var cached = recent[i];
      if (cached.source == source) {
        if (i != 0) {
          recent.splice(i, 1);
          recent.unshift(cached);
        }
        return cached.scalars;
      }
    }

    var scalars:Array<Int> = [];
    var iterator = new StringIteratorUnicode(source);
    while (iterator.hasNext()) {
      var codepoint = iterator.next();
      if (codepoint < 0 || codepoint > 0x10FFFF ||
          (codepoint >= 0xD800 && codepoint <= 0xDFFF))
        throw 'Invalid Unicode scalar in Text';
      scalars.push(codepoint);
    }

    if (scalars.length <= MAX_CACHED_SCALARS) {
      recent.unshift({source:source, scalars:scalars});
      if (recent.length > MAX_ENTRIES) recent.pop();
    }
    return scalars;
  }

  public static function length(source:String):Int return points(source).length;

  /** Caller validates bounds using the length and the existing numeric
      index checks (which also cover the opt-in Exact-number dialect). */
  public static function at(source:String, position:Int):String
    return String.fromCharCode(points(source)[position]);
}
