package nail;

import nail.BootRuntime;
import nail.Parser;
import nail.SyntaxEncoder;
import haxe.ds.StringMap;
import nail.SourceProvenance.SourceOrigin;
import nail.Ast.Expr;
import nail.Ast.Form;
import nail.ResultValue;
import nail.SourcePositions.SourceSpan;
import nail.SourcePositions.SourceToken;
import nail.Value;

/** Structured diagnostics for the experimental Nail-written HM checker.
    Haxe only converts the existing Nail Result and uses the independent,
    already-shipped source-position scanner. No Haxe TypeChecker or host
    parser is involved in the actual type decision.

    The Nail checker emits an expression-child path and the failing form's
    ordinal. Existing host parser provenance may resolve those coordinates
    for original (non-generated) expression nodes; it is *never* used for
    type decisions. Unresolvable generated nodes receive no fake offsets. */
typedef NailCheckDiagnostic = {
  final phase:String;
  final message:String;
  final span:Null<SourceSpan>;
  final templateSpan:Null<SourceSpan>;
  /** Origin may belong to a different module; offsets refer to its source. */
  final templateOrigin:Null<SourceOrigin>;
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
      var macroDeclaration = unique(tokens, 'macro');
      var hasMacro = false;
      for (token in tokens) if (token.text == 'macro') hasMacro = true;
      var expansion = hasMacro ? unique(tokens, 'expand') : null;
      var quote = hasMacro ? unique(tokens, 'quote') : null;
      // Do not blame an unrelated macro expansion for a failing match
      // outside the quoted template. Only one macro declaration, one quote,
      // one match and one later call justify this provisional origin pair.
      if (macroDeclaration != null && quote != null && pattern != null
          && expansion != null && macroDeclaration.start < quote.start
          && quote.start < pattern.start && pattern.start < expansion.start) {
        span = expansion;
        template = pattern;
      } else if (!hasMacro) span = pattern;
    }
    return {span:span,template:template};
  }

  /** Original semicolon-delimited form spans, excluding the modern header
      and macro directives erased by source expansion. Quoted Text tokens
      have already been atomized by SourcePositions.scan. */
  static function sourceForms(tokens:Array<SourceToken>):Array<SourceSpan> {
    var result:Array<SourceSpan> = [];
    var first = 0;
    if (tokens.length >= 3 && tokens[0].text == 'nail'
        && tokens[2].text == ';') first = 3;
    var depth = 0;
    var start = first;
    for (i in first...tokens.length) {
      var word = tokens[i].text;
      if (word == '(' || word == '[' || word == '{') depth++;
      if (word == ')' || word == ']' || word == '}') depth--;
      if (depth < 0) return [];
      if (word == ';' && depth == 0) {
        if (i >= start) {
          var head = tokens[start].text;
          if (head != 'macro' && head != 'import' && head != 'export') {
            var span = SourcePositions.span(tokens,start,i + 1);
            if (span != null) result.push(span);
          }
        }
        start = i + 1;
      }
    }
    if (depth != 0 || start != tokens.length) return [];
    return result;
  }

  static function trail(fault:Value):Null<{index:Int,path:Array<Int>}> {
    return switch (fault) {
      case SyntaxNode('TCFault',Cons(_,Cons(
          SyntaxNode('TCPath',steps),Cons(SyntaxNode('TCFormTrail',forms),Nil)))):
        var formIndex = -1;
        var cursor:Value = forms;
        while (true) switch (cursor) {
          case Cons(_,rest): formIndex++; cursor=rest;
          case Nil: break;
          case _: return null;
        }
        var path:Array<Int> = [];
        cursor = steps;
        while (true) switch (cursor) {
          case Cons(SyntaxLeaf('TCStep',label),rest):
            var part=Std.parseInt(StringTools.trim(label));
            if (part == null || part < 0 || part > 2) return null;
            path.push(part);
            cursor=rest;
          case Nil: break;
          case _: return null;
        }
        {index:formIndex,path:path};
      case _: null;
    };
  }

  static function uniqueInForm(tokens:Array<SourceToken>,
      word:String,area:SourceSpan):Null<SourceSpan> {
    var found:Null<SourceSpan> = null;
    for (token in tokens) {
      if (token.start < area.start || token.end > area.end
          || token.text != word) continue;
      if (found != null) return null;
      found = tokenSpan(token);
    }
    return found;
  }

  /** Read-only provenance projection. The original Haxe parser here is
      optional and NEVER checks the program; Nail supplies the exact failed
      structural child path. Generated macro nodes may lack source locations. */
  static function originalExpression(source:String,area:SourceSpan,
      path:Array<Int>,label:String):Null<SourceSpan> {
    try {
      var parser = new Parser(source);
      var forms = parser.parseRaw();
      for (form in forms) {
        var formSpan = parser.provenance.spanOfForm(form);
        if (formSpan == null || formSpan.start != area.start
            || formSpan.end != area.end) continue;
        var expr:Expr = switch (form) {
          case Define(_,body) | Evaluate(body): body;
          case _: return null;
        };
        for (step in path) {
          expr = switch (expr) {
            case Lambda(_,body) if (step == 1): body;
            case Apply(fn,arg) if (step == 0): fn;
            case Apply(fn,arg) if (step == 1): arg;
            case If(test,yes,no) if (step == 0): test;
            case If(test,yes,no) if (step == 1): yes;
            case If(test,yes,no) if (step == 2): no;
            case _: return null;
          };
        }
        return switch (expr) {
          case Var(name) if (name == label):
            parser.provenance.spanOfExpression(expr);
          case _: null;
        };
      }
    } catch (_:Dynamic) {
      // This parser does not yet support every experimental typed surface
      // form. A provenance failure must not affect a Nail type decision.
    }
    return null;
  }

  /** Match type-error provenance by form ordinal and AST child path.
      Name matching is only a safety check, never a substitute for a traced
      path when multiple tokens occur inside one original expression. */
  static function tracedLocation(source:String,message:String,
      tokens:Array<SourceToken>,fault:Value):Null<SourceSpan> {
    var sourceTrail = trail(fault);
    if (sourceTrail == null) return null;
    var forms = sourceForms(tokens);
    if (sourceTrail.index < 0 || sourceTrail.index >= forms.length)
      return null;
    var name = after(message,'Unknown name:');
    if (name == null || StringTools.startsWith(name,'#')) return null;
    var area = forms[sourceTrail.index];
    var exact = originalExpression(source,area,sourceTrail.path,name);
    if (exact != null) return exact;
    // Even if the optional host parser cannot handle this syntax, a unique
    // matching token *within the traced failing form* is still unambiguous.
    return uniqueInForm(tokens,name,area);
  }

  /** SourceProvenance may carry the whole original invocation as a
      recovery span. Narrow a verified expansion origin to its actual keyword,
      never to another occurrence with the same spelling. */
  static function callKeyword(tokens:Array<SourceToken>,site:SourceSpan):SourceSpan {
    for (token in tokens)
      if (token.text == 'expand' && token.start == site.start)
        return tokenSpan(token);
    return site;
  }

  /** Replay only the already-defined hygienic macro AST rewrite with a
      read-only provenance sidecar. Nail's error contains the actual failed
      form/child path. This pass never infers a type and emits no bytecode.
      For locally declared macros, both origins are taken from the parser's
      original token identities; multiple expansions are distinguished. */
  static function macroOrigin(source:String, fault:Value, message:String,
      sourceId:String, ?modules:String->Null<String>):Null<{
        span:SourceSpan,template:Null<SourceSpan>,
        templateOrigin:Null<SourceOrigin>}> {
    var sourceTrail = trail(fault);
    if (sourceTrail == null) return null;
    try {
      var parser = new Parser(source);
      parser.provenance.sourceId = sourceId;
      var expanded = MacroExpander.forms(parser.parseRaw(),
        parser.provenance, modules);
      if (sourceTrail.index < 0 || sourceTrail.index >= expanded.length)
        return null;

      var expr:Expr = switch (expanded[sourceTrail.index]) {
        case Define(_,body) | Evaluate(body): body;
        case _: return null;
      };
      var ancestry:Array<Expr> = [expr];
      for (step in sourceTrail.path) {
        expr = switch (expr) {
          case Lambda(_,body) if (step == 1): body;
          case Apply(fn,arg) if (step == 0): fn;
          case Apply(fn,arg) if (step == 1): arg;
          case If(test,yes,no) if (step == 0): test;
          case If(test,yes,no) if (step == 1): yes;
          case If(test,yes,no) if (step == 2): no;
          case _: return null;
        };
        ancestry.push(expr);
      }

      var missing = after(message,'Unknown name:');
      if (missing != null) {
        // Assert the structurally selected node is the actual failed symbol.
        // Hygiene-qualified names resolve against their source spelling.
        var matching = switch (expr) {
          case Var(label):
            label == missing
              || MacroExpander.globalName(label) == MacroExpander.globalName(missing);
          case _: false;
        };
        if (!matching) return null;
        // A captured caller argument inserted through unquote retains its
        // *own* source span, not its containing expansion's call site.
        var call = parser.provenance.expansionSiteOfExpression(expr);
        var direct = parser.provenance.spanOfExpression(expr);
        if (call == null) {
          if (direct == null) return null;
          return {span:direct,template:null,templateOrigin:null};
        }
        return {span:callKeyword(parser.tokenPositions,call),
          template:parser.provenance.templateOfExpression(expr),
          templateOrigin:parser.provenance.templateOriginOfExpression(expr)};
      }

      // Pattern failures are detected before traversing the lowered match
      // body. Walk back toward the current expression's containing macro
      // node, not an unrelated expansion elsewhere in the file.
      var pattern = StringTools.startsWith(message,'Non-exhaustive match:')
        || StringTools.startsWith(message,'Mixed constructors in algebraic match')
        || StringTools.startsWith(message,
          'Constructor match binding arity mismatch:');
      var generatedTypeFailure = StringTools.startsWith(message,
          'No numeric relation instance')
        || StringTools.startsWith(message,'No relation instance:')
        || StringTools.startsWith(message,'Numeric operands require concrete types')
        || StringTools.startsWith(message,'Type mismatch')
        || StringTools.startsWith(message,'Eq constraint requires')
        || StringTools.startsWith(message,'Projection requires a record')
        || StringTools.startsWith(message,'Missing structural field:');
      if (!pattern && !generatedTypeFailure) return null;
      var i = ancestry.length;
      while (i > 0) {
        var origin = ancestry[--i];
        var call = parser.provenance.expansionSiteOfExpression(origin);
        if (call != null)
          return {span:callKeyword(parser.tokenPositions,call),
            template:parser.provenance.templateOfExpression(origin),
            templateOrigin:parser.provenance.templateOriginOfExpression(origin)};
      }
    } catch (_:Dynamic) {
      // The provenance replay is optional. A module resolver error or
      // unsupported experimental syntax must not invent an origin.
    }
    return null;
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
  public static function analyze(source:String, ?boot:BootRuntime,
      ?modules:String->Null<String>, sourceId:String = '<source>'):NailCheckReport {
    var runtime = boot == null ? new BootRuntime(60000000) : boot;
    var result:Value;
    // One snapshot per logical module in this analysis request. The host
    // syntax expander and provenance replay see identical module contents.
    var loaded = new StringMap<String>();
    var attempted = new StringMap<Bool>();
    var cachedModules:Null<String->Null<String>> = modules == null ? null
      : (name:String) -> {
        if (!attempted.exists(name)) {
          attempted.set(name,true);
          loaded.set(name,modules(name));
        }
        return loaded.get(name);
      };
    try {
      if (cachedModules == null)
        result = runtime.invoke('tcCheckSourceTraced', Text(source));
      else {
        // Imported macro syntax is expanded by the existing host parser;
        // the resulting Syntax is inferred ONLY by the Nail bytecode checker.
        var parser = new Parser(source);
        parser.provenance.sourceId = sourceId;
        var expanded = parser.parse(cachedModules);
        result = runtime.invoke('tcCheckSyntaxTraced',
          SyntaxEncoder.program(expanded));
      }
    } catch (error:Dynamic) {
      return {ok:false, types:[], diagnostics:[{phase:'macro',
        message:Std.string(error), span:null, templateSpan:null,
        templateOrigin:null}]};
    }

    var tag:String;
    try tag = ResultValue.tag(result)
    catch (error:Dynamic) {
      return {ok:false, types:[], diagnostics:[{phase:'internal',
        message:Std.string(error), span:null, templateSpan:null,
        templateOrigin:null}]};
    }

    if (tag == ResultValue.OK)
      return {ok:true, diagnostics:[],
        types:pretty(runtime, ResultValue.get(result, ResultValue.OK))};

    var fault = ResultValue.get(result, ResultValue.ERR);
    var message = switch (fault) {
      case SyntaxNode('TCFault',Cons(SyntaxLeaf('TCMessage',text),_)): text;
      case Text(text): text;
      case _: throw 'Unexpected traced Nail checker Error representation';
    };
    // The Nail source language permits whitespace inside quoted Text
    // literals; keep the exact original message while normalizing only
    // the copy used for diagnostic classification and token lookup.
    var lookupMessage = StringTools.trim(message);
    var macroError = isMacroError(lookupMessage);
    var located:{span:Null<SourceSpan>,template:Null<SourceSpan>,
      templateOrigin:Null<SourceOrigin>} =
      {span:null,template:null,templateOrigin:null};
    // Even if scanning fails (e.g. an unterminated quote), never attach an
    // offset invented by a second parser or replace Nail's error message.
    try {
      var tokens = SourcePositions.scan(source);
      located = locate(lookupMessage,tokens,macroError);
      if (!macroError) {
        var span = tracedLocation(source,lookupMessage,tokens,fault);
        if (span != null) located.span=span;
        // Replay when macros are local or when an explicit module resolver
        // was supplied. Imported templates retain their own logical source.
        var hasMacro = cachedModules != null;
        for (token in tokens) if (token.text == 'macro') hasMacro = true;
        if (hasMacro) {
          var origin = macroOrigin(source,fault,lookupMessage,
            sourceId,cachedModules);
          if (origin != null) {
            located.span=origin.span;
            located.template=origin.template;
            located.templateOrigin=origin.templateOrigin;
          }
        }
      }
    } catch (_:Dynamic) {
      // Attribution is best-effort, but the Nail checker error is authoritative.
    }

    return {ok:false,types:[],diagnostics:[{
      phase:macroError ? 'macro' : 'type', message:message,
      span:located.span, templateSpan:located.template,
      templateOrigin:located.templateOrigin
    }]};
  }
}
