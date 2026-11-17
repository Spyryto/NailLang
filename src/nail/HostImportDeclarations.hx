package nail;

import nail.NType;
import nail.SourcePositions.SourceToken;

/** Opt-in, module-only runtime imports for Nail 0.53.
    Syntactic sugar for the existing signed, typed public module manifest:
    nothing about the ByteVm or the source-free compiler is changed.
    The declaration is erased before BOTH Haxe and Nail compilers run;
    whitespace/newlines preserve source coordinates for diagnostics. */
typedef ParsedHostImport = {
  var symbol:String;
  var alias:String;
  var type:NType;
}

typedef HostImportExtraction = {
  var source:String;
  var imports:Array<ParsedHostImport>;
}

class HostImportDeclarations {
  public static inline var VERSION = '0.53';
  public static inline var MAX_IMPORTS = 64;
  public static inline var MAX_TYPE_DEPTH = 24;

  static function error(message:String, ?token:SourceToken):Dynamic
    return 'Host import: ' + message
      + (token == null ? '' : ' at ' + token.line + ':' + token.column);

  static function expect(words:Array<String>, pos:Array<Int>, expected:String):Void {
    if (pos[0] >= words.length || words[pos[0]] != expected)
      throw error('expected ' + expected);
    pos[0]++;
  }

  /** Closed, monomorphic host types only. Arrow associates to the right. */
  static function atom(words:Array<String>, pos:Array<Int>, depth:Int):NType {
    if (depth > MAX_TYPE_DEPTH) throw error('type nesting limit exceeded');
    if (pos[0] >= words.length) throw error('missing type');
    var name=words[pos[0]++];
    return switch(name) {
      case 'Text': TText;
      case 'Bool': TBoolean;
      case 'Int': TInt;
      case 'Ratio': TRatio;
      case 'Float': TFloat;
      case 'List':
        expect(words,pos,'[');
        var item=parseType(words,pos,depth+1);
        expect(words,pos,']');
        TList(item);
      case 'CoreResult':
        expect(words,pos,'[');
        var ok=parseType(words,pos,depth+1);
        expect(words,pos,',');
        var fail=parseType(words,pos,depth+1);
        expect(words,pos,']');
        TSum('CoreResult',[ok,fail]);
      case _:
        throw error('unsupported type ' + name);
    };
  }

  static function parseType(words:Array<String>, pos:Array<Int>, depth:Int):NType {
    var head=atom(words,pos,depth);
    if (pos[0] < words.length && words[pos[0]] == '->') {
      pos[0]++;
      return TFunction(head,parseType(words,pos,depth+1));
    }
    return head;
  }

  static function readType(tokens:Array<SourceToken>, start:Int, end:Int):NType {
    if (start >= end) throw error('missing typed signature',tokens[start-1]);
    var words=[for (i in start...end) tokens[i].text];
    var pos=[0];
    var signature=parseType(words,pos,0);
    if (pos[0] != words.length)
      throw error('unexpected type token ' + words[pos[0]],tokens[start+pos[0]]);
    return signature;
  }

  /** Scan top-level declarations without touching static expression-macro
      imports (import x from OtherModule ;) or quoted strings. A runtime
      import can appear before or after the consuming definition: it is a
      module-scoped declaration, not a sequential statement. */
  public static function extract(source:String, enabled:Bool):HostImportExtraction {
    if (!enabled) return {source:source,imports:[]};
    var tokens=SourcePositions.scan(source);
    var imports:Array<ParsedHostImport> = [];
    var removed:Array<{start:Int,end:Int}> = [];
    var depth=0;
    var i=0;
    while (i < tokens.length) {
      var word=tokens[i].text;
      // Only declarations immediately after a semicolon can be top-level.
      if (depth == 0 && word == 'import' &&
          (i == 0 || tokens[i-1].text == ';')) {
        var j=i+1;
        if (j >= tokens.length) throw error('incomplete import',tokens[i]);
        var symbol=tokens[j++].text;
        var alias=symbol;
        if (j < tokens.length && tokens[j].text == 'as') {
          j++;
          if (j >= tokens.length) throw error('missing alias',tokens[i]);
          alias=tokens[j++].text;
        }
        if (j < tokens.length && tokens[j].text == 'from') {
          j++;
          if (j < tokens.length && tokens[j].text == 'NailHost') {
            j++;
            if (!ModuleImage.validName(symbol) ||
                !ModuleImage.validName(alias))
              throw error('invalid symbol or alias',tokens[i]);
            if (j >= tokens.length || tokens[j].text != ':')
              throw error('NailHost requires an explicit type',tokens[i]);
            j++;
            var typeStart=j;
            while (j < tokens.length && tokens[j].text != ';') j++;
            if (j >= tokens.length)
              throw error('missing import terminator',tokens[i]);
            if (imports.length >= MAX_IMPORTS)
              throw error('too many host imports',tokens[i]);
            imports.push({symbol:symbol,alias:alias,
              type:readType(tokens,typeStart,j)});
            removed.push({start:tokens[i].start,end:tokens[j].end});
            i=j+1;
            continue;
          }
        }
      }
      switch(word) {
        case '(' | '[' | '{': depth++;
        case ')' | ']' | '}':
          depth--;
          if (depth < 0) depth=0; // Core parser diagnoses unmatched forms.
        case _:
      }
      i++;
    }
    if (removed.length == 0) return {source:source,imports:imports};
    var out=new StringBuf();
    var offset=0;
    for (range in removed) {
      out.add(source.substring(offset,range.start));
      var taken=source.substring(range.start,range.end);
      for (k in 0...taken.length) {
        var ch=taken.charAt(k);
        out.add(ch == '\n' || ch == '\r' ? ch : ' ');
      }
      offset=range.end;
    }
    out.add(source.substring(offset));
    return {source:out.toString(),imports:imports};
  }
}
