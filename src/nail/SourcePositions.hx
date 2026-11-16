package nail;

/** Source coordinates for the host parser's whitespace-delimited surface tokens.
    This is deliberately a sidecar: existing AST and bootstrap encoding stay unchanged.
    Coordinates are UTF-16 offsets, 1-based lines and columns. */
typedef SourceToken = {
  final text:String;
  final start:Int;
  final end:Int;
  final line:Int;
  final column:Int;
  final endLine:Int;
  final endColumn:Int;
}

/** Half-open range in the original source. Offsets use Haxe String units. */
typedef SourceSpan = {
  final start:Int;
  final end:Int;
  final line:Int;
  final column:Int;
  final endLine:Int;
  final endColumn:Int;
}

class SourcePositions {
  static final whitespace = ~/\s/;

  /** Scan tokens without losing offsets, including strings and comments.
      The parser uses a standalone quote token and joins its interior words. */
  public static function scan(source:String):Array<SourceToken> {
    var out:Array<SourceToken> = [];
    var pos = 0;
    var line = 1;
    var column = 1;
    var quoted = false;
    var comment = false;
    var parts:Array<String> = [];
    var quoteStart = 0;
    var quoteLine = 0;
    var quoteColumn = 0;
    while (pos < source.length) {
      var ch = source.charAt(pos);
      if (ch == '\n') {
        pos++;
        line++;
        column = 1;
        comment = false;
        continue;
      }
      if (comment) { pos++; column++; continue; }
      if (whitespace.match(ch)) { pos++; column++; continue; }
      var start = pos;
      var startLine = line;
      var startColumn = column;
      while (pos < source.length && !whitespace.match(source.charAt(pos))) {
        pos++;
        column++;
      }
      var word = source.substring(start, pos);
      if (quoted) {
        if (word == '"') {
          var decoded:String;
          try decoded = haxe.Json.parse('"' + parts.join(' ') + '"')
          catch (e:Dynamic) throw 'Invalid string escape: ' + Std.string(e);
          out.push({text:'\u0001' + decoded, start:quoteStart, end:pos, line:quoteLine, column:quoteColumn, endLine:line, endColumn:column});
          quoted = false;
          parts = [];
        } else parts.push(word);
      } else if (StringTools.startsWith(word, '#')) {
        comment = true;
      } else if (word == '"') {
        quoted = true;
        quoteStart = start;
        quoteLine = startLine;
        quoteColumn = startColumn;
        parts = [];
      } else out.push({text:word, start:start, end:pos, line:startLine, column:startColumn, endLine:line, endColumn:column});
    }
    if (quoted) throw 'Unterminated string literal';
    return out;
  }

  /** Span of [first, afterLast) token indices. The parsed core can carry this
      span in a side table without adding a sixth expression constructor. */
  public static function span(tokens:Array<SourceToken>, first:Int, afterLast:Int):Null<SourceSpan> {
    if (first < 0 || afterLast <= first || afterLast > tokens.length) return null;
    var begin = tokens[first];
    var end = tokens[afterLast - 1];
    return {start:begin.start, end:end.end, line:begin.line, column:begin.column,
      endLine:end.endLine, endColumn:end.endColumn};
  }

  public static function texts(source:String):Array<String>
    return [for (token in scan(source)) token.text];
}
