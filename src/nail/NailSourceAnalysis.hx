package nail;

import nail.BootRuntime;
import nail.ResultValue;
import nail.SourcePositions.SourceSpan;
import nail.SourcePositions.SourceToken;
import nail.Value;

/** Structured diagnostics for the experimental Nail-written HM checker.
    Haxe only converts the existing Nail Result and uses the independent,
    already-shipped source-position scanner. No Haxe TypeChecker or host
    parser is involved in the actual type decision.

    Locations are deliberately conservative: a unique source token may be
    pinpointed, and an unambiguous macro call may be used as an expansion
    site. Otherwise span is null; generated trees receive no fake offsets. */
typedef NailCheckDiagnostic = {
  final phase:String;
  final message:String;
  final span:Null<SourceSpan>;
  final templateSpan:Null<SourceSpan>;
}

typedef NailCheckReport = {
  final ok:Bool;
  final diagnostics:Array<NailCheckDiagnostic>;
  final types:Array<String>;
}

class NailSourceAnalysis {
  static function tokenSpan(token:SourceToken):SourceSpan
    return {start:token.start, end:token.end, line:token.line,
      column:token.column, endLine:token.endLine, endColumn:token.endColumn};

  static function unique(tokens:Array<SourceToken>, word:String):Null<SourceSpan> {
    var found:Null<SourceSpan> = null;
    for (token in tokens) {
      if (token.text != word) continue;
      if (found != null) return null;
      found = tokenSpan(token);
    }
    return found;
  }

  static function distinct(tokens:Array<SourceToken>,
      left:String, right:String):Null<SourceSpan> {
    var found:Null<SourceSpan> = null;
    for (token in tokens) {
      if (token.text != left && token.text != right) continue;
      if (found != null) return null;
      found = tokenSpan(token);
    }
    return found;
  }

  static function repeatedDefinition(tokens:Array<SourceToken>,
      keyword:String, name:String):Null<SourceSpan> {
    var entries:Array<SourceSpan> = [];
    for (i in 0...(tokens.length - 1))
      if (tokens[i].text == keyword && tokens[i + 1].text == name)
        entries.push(tokenSpan(tokens[i + 1]));
    // The Nail checker stops at the second declaration. More than two
    // duplicate declarations make the failing occurrence unverifiable.
    return entries.length == 2 ? entries[1] : null;
  }

  static function after(message:String, prefix:String):Null<String> {
    // Nail quoted Text strips delimiter whitespace: concatenated diagnostics
    // may be "Unknown name:missing" rather than "Unknown name: missing".
    if (!StringTools.startsWith(message, prefix)) return null;
    var label = StringTools.trim(message.substr(prefix.length));
    return label.length == 0 ? null : label;
  }

  static function isMacroError(message:String):Bool
    return StringTools.startsWith(message, 'unknown macro ')
      || StringTools.startsWith(message, 'unknown unquote ')
      || StringTools.startsWith(message, 'duplicate macro ')
      || StringTools.startsWith(message, 'macro ')
      || StringTools.startsWith(message, 'Macro ')
      || message.indexOf('macro import') >= 0;

  static function locate(message:String, tokens:Array<SourceToken>,
      macroError:Bool):{span:Null<SourceSpan>,template:Null<SourceSpan>} {
    var span:Null<SourceSpan> = null;
    var template:Null<SourceSpan> = null;
    var label:Null<String> = null;

    label = after(message, 'Unknown name:');
    if (label == null) label = after(message, 'Unknown type:');
    if (label == null) label = after(message, 'Unknown algebraic constructor in match:');
    if (label != null) span = unique(tokens, label);

    var duplicate = after(message, 'Duplicate definition:');
    if (duplicate != null)
      span = repeatedDefinition(tokens, 'def', duplicate);
    duplicate = after(message, 'Duplicate structural alias:');
    if (duplicate != null)
      span = repeatedDefinition(tokens, 'type', duplicate);

    if (macroError) {
      label = after(message, 'unknown macro ');
      if (label != null) span = unique(tokens, label);
      label = after(message, 'duplicate macro ');
      if (label != null) span = repeatedDefinition(tokens, 'macro', label);
      return {span:span, template:null};
    }

    if (StringTools.startsWith(message, 'Non-exhaustive match:')
      || StringTools.startsWith(message, 'Mixed constructors in algebraic match')
      || StringTools.startsWith(message, 'Constructor match binding arity mismatch:')) {
      var pattern = distinct(tokens, 'match', 'function');
      // A unique expansion site is meaningful for one macro-generated
      // pattern. Multiple expansions cannot be distinguished yet.
      var hasMacro = false;
      for (token in tokens) if (token.text == 'macro') hasMacro = true;
      var expansion = hasMacro ? unique(tokens, 'expand') : null;
      if (expansion != null && pattern != null) {
        span = expansion;
        template = pattern;
      } else if (!hasMacro) span = pattern;
    }
    return {span:span,template:template};
  }

  static function pretty(boot:BootRuntime, checked:Value):Array<String> {
    var output:Array<String> = [];
    var entries:Value = switch (checked) {
      case SyntaxNode('TCChecked', items): items;
      case _: throw 'Unexpected Nail checker success representation';
    };
    while (true) switch (entries) {
      case Nil: break;
      case Cons(item, rest):
        switch (boot.invoke('tcPretty', item)) {
          case Text(shown): output.push(shown);
          case _: throw 'Unexpected Nail type pretty-printer result';
        }
        entries = rest;
      case _: throw 'Invalid Nail checker result list';
    }
    return output;
  }

  /** Read-only per-source report, using the same Nail bytecode image on Haxe,
      JavaScript and PHP. The optional BootRuntime lets callers reuse the
      compiled source-free image across queries without compiler mutations. */
  public static function analyze(source:String, ?boot:BootRuntime):NailCheckReport {
    var runtime = boot == null ? new BootRuntime(60000000) : boot;
    var result:Value;
    try result = runtime.invoke('tcCheckSource', Text(source))
    catch (error:Dynamic) {
      return {ok:false, types:[], diagnostics:[{phase:'internal',
        message:Std.string(error), span:null, templateSpan:null}]};
    }

    var tag:String;
    try tag = ResultValue.tag(result)
    catch (error:Dynamic) {
      return {ok:false, types:[], diagnostics:[{phase:'internal',
        message:Std.string(error), span:null, templateSpan:null}]};
    }

    if (tag == ResultValue.OK)
      return {ok:true, diagnostics:[],
        types:pretty(runtime, ResultValue.get(result, ResultValue.OK))};

    var message = switch (ResultValue.get(result, ResultValue.ERR)) {
      case Text(s): s;
      case _: throw 'Unexpected Nail checker Error representation';
    };
    // The Nail source language permits whitespace inside quoted Text
    // literals; keep the exact original message while normalizing only
    // the copy used for diagnostic classification and token lookup.
    var lookupMessage = StringTools.trim(message);
    var macroError = isMacroError(lookupMessage);
    var located:{span:Null<SourceSpan>,template:Null<SourceSpan>} =
      {span:null,template:null};
    // Even if scanning fails (e.g. an unterminated quote), never attach an
    // offset invented by a second parser or replace Nail's error message.
    try located = locate(lookupMessage, SourcePositions.scan(source), macroError)
    catch (_:Dynamic) {}

    return {ok:false,types:[],diagnostics:[{
      phase:macroError ? 'macro' : 'type', message:message,
      span:located.span, templateSpan:located.template
    }]};
  }
}
