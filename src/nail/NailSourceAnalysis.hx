package nail;

import nail.BootRuntime;
import nail.Parser;
import nail.MacroExpander;
import nail.MacroModuleDialect;
import nail.NailMacroModuleInputs;
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
      macroError:Bool):{span:Null<SourceSpan>,template:Null<SourceSpan>,
      templateOrigin:Null<SourceOrigin>} {
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
      return {span:span, template:null,templateOrigin:null};
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
    return {span:span,template:template,templateOrigin:null};
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

  /** Resolve Nail-owned symbolic origin against original source tokens.
      No macro replay or host macro expansion occurs here. Only a unique
      template name within its original declaration can receive a span. */
  /** Read-only projections of Nail's *already parsed* Syntax. There is
      no second source parser, no macro substitution and no type decision. */
  static function syntaxChildren(value:Value):Array<Value> {
    var output:Array<Value>=[];
    var rest:Value=switch(value) {
      case SyntaxNode(_,items): items;
      case _: return output;
    };
    while (true) switch(rest) {
      case Nil: return output;
      case Cons(item,tail): output.push(item);rest=tail;
      case _: return [];
    }
    return output;
  }

  static function findModuleProgram(modules:Value,name:String):Null<Value> {
    for (entry in syntaxChildren(modules)) switch(entry) {
      case SyntaxNode('TCBinding',Cons(SyntaxLeaf('TCName',owner),
          Cons(program,Nil))) if (owner==name): return program;
      case _:
    }
    return null;
  }

  static function templateSyntax(program:Value,macroName:String):Null<Value> {
    for (form in syntaxChildren(program)) switch(form) {
      case SyntaxNode('Define',Cons(
          SyntaxLeaf('Name',label),Cons(body,Nil)))
          if (label=='#macro_decl_'+macroName):
        var cur=body;
        while (true) switch(cur) {
          case SyntaxNode('Lambda',Cons(_,Cons(rest,Nil))):
            cur=rest;
          case SyntaxNode('Apply',Cons(
              SyntaxLeaf('Var','#macro_quote'),Cons(template,Nil))):
            return template;
          case _: return null;
        }
      case _:
    }
    return null;
  }

  static function templateAtPath(template:Value,path:String):Null<Value> {
    var node:Value=template;
    for (i in 0...path.length) {
      var digit=path.charCodeAt(i)-48;
      var parts=syntaxChildren(node);
      if (digit<0 || digit>=parts.length) return null;
      node=parts[digit];
    }
    return node;
  }

  static function numericSymbol(name:String):Null<String> return switch(name) {
    case '#modern+' | '+': '+';
    case '#modern-' | '-': '-';
    case '#modern*' | '*': '*';
    case '#modern/' | '/': '/';
    case _: null;
  };

  static function nodeTokenHint(node:Value):Null<String> {
    return switch(node) {
      case SyntaxNode('Apply',Cons(
          SyntaxNode('Apply',Cons(SyntaxLeaf('Var',name),_)),_)):
        numericSymbol(name);
      case SyntaxNode('If',_): 'if';
      case SyntaxNode('Apply',Cons(SyntaxLeaf('Var',name),_))
          if (!StringTools.startsWith(name,'#macro_')):
        name;
      case SyntaxLeaf('Var',name):
        if (StringTools.startsWith(name,'#macro_global_'))
          name.substr('#macro_global_'.length)
        else if (StringTools.startsWith(name,'#macro_local_')) null
        else name;
      case _: null;
    }
  }

  /** AST-based *infix order*, used only to disambiguate repeated numeric
      tokens in one macro declaration. A mismatch with actual source token
      counts fails closed rather than assigning a speculative position. */
  static function syntaxOperatorOrder(node:Value,path:String,
      out:Array<{path:String,token:String}>):Void {
    switch(node) {
      case SyntaxNode('Apply',Cons(
          SyntaxNode('Apply',Cons(
            SyntaxLeaf('Var',name),Cons(left,Nil))),
          Cons(right,Nil))) if (numericSymbol(name)!=null):
        syntaxOperatorOrder(left,path+'01',out);
        out.push({path:path,token:numericSymbol(name)});
        syntaxOperatorOrder(right,path+'1',out);
      case SyntaxNode('Apply',Cons(fn,Cons(arg,Nil))):
        syntaxOperatorOrder(fn,path+'0',out);
        syntaxOperatorOrder(arg,path+'1',out);
      case SyntaxNode('Lambda',Cons(_,Cons(body,Nil))):
        syntaxOperatorOrder(body,path+'1',out);
      case SyntaxNode('If',Cons(test,Cons(yes,Cons(no,Nil)))):
        out.push({path:path,token:'if'});
        syntaxOperatorOrder(test,path+'0',out);
        syntaxOperatorOrder(yes,path+'1',out);
        syntaxOperatorOrder(no,path+'2',out);
      case _:
    }
  }

  /** Only look inside the selected macro declaration, keeping tokens from
      other macros, string contents and module headers out of attribution. */
  static function templateTokenSpan(source:String,macroName:String,
      template:Value,path:String,selected:Value,
      ?preferred:String):Null<SourceSpan> {
    var hint=preferred==null ? nodeTokenHint(selected) : preferred;
    if (hint==null || hint.length==0) return null;
    var tokens=SourcePositions.scan(source);
    var matches:Array<SourceSpan>=[];
    var declarations=0;
    for (i in 0...tokens.length-1) {
      if (tokens[i].text!='macro' || tokens[i+1].text!=macroName)
        continue;
      declarations++;
      var nesting=0;
      for (j in i+2...tokens.length) {
        var word=tokens[j].text;
        if (word=='(' || word=='[' || word=='{') nesting++;
        if (word==')' || word==']' || word=='}') nesting--;
        if (nesting==0 && word==';') break;
        if (word==hint) matches.push(tokenSpan(tokens[j]));
      }
    }
    if (declarations!=1 || matches.length==0) return null;
    if (matches.length==1) return matches[0];
    var order:Array<{path:String,token:String}>=[];
    syntaxOperatorOrder(template,'',order);
    var same=[for (item in order) if (item.token==hint) item];
    if (same.length!=matches.length) return null;
    for (i in 0...same.length)
      if (same[i].path==path) return matches[i];
    return null;
  }

  /** Read-only caller-site mapping. Nail already carried the structural
      invocation path across nested expansions; only the original Nail-parsed
      Syntax and the scanner's actual keyword tokens are consulted here. */
  static function originalMacroName(expr:Value):Null<String> return switch(expr) {
    case SyntaxNode('Apply',Cons(SyntaxLeaf('Var','#macro_expand'),
        Cons(SyntaxLeaf('Var',name),Nil))): name;
    case SyntaxNode('Apply',Cons(fn,Cons(_,Nil))): originalMacroName(fn);
    case _: null;
  };

  static function originalMacroArgs(expr:Value,path:String,
      out:Array<{expr:Value,path:String}>):Void {
    switch(expr) {
      case SyntaxNode('Apply',Cons(SyntaxLeaf('Var','#macro_expand'),
          Cons(SyntaxLeaf('Var',_),Nil))): return;
      case SyntaxNode('Apply',Cons(fn,Cons(arg,Nil))):
        out.unshift({expr:arg,path:path+'1'});
        originalMacroArgs(fn,path+'0',out);
      case _: return;
    }
  }

  static function originalMacroCallOrder(expr:Value,path:String,
      out:Array<{name:String,path:String}>):Void {
    var name=originalMacroName(expr);
    if (name!=null) {
      out.push({name:name,path:path});
      var arguments:Array<{expr:Value,path:String}>=[];
      originalMacroArgs(expr,path,arguments);
      for (argument in arguments)
        originalMacroCallOrder(argument.expr,argument.path,out);
      return;
    }
    switch(expr) {
      case SyntaxNode('Apply',Cons(fn,Cons(arg,Nil))):
        originalMacroCallOrder(fn,path+'0',out);
        originalMacroCallOrder(arg,path+'1',out);
      case SyntaxNode('Lambda',Cons(_,Cons(body,Nil))):
        originalMacroCallOrder(body,path+'1',out);
      case SyntaxNode('If',Cons(test,Cons(yes,Cons(no,Nil)))):
        originalMacroCallOrder(test,path+'0',out);
        originalMacroCallOrder(yes,path+'1',out);
        originalMacroCallOrder(no,path+'2',out);
      case _:
    }
  }

  static function originalFormAt(program:Value,index:Int):Null<Value> {
    var current=0;
    for (form in syntaxChildren(program)) {
      var erased=switch(form) {
        case SyntaxNode('Define',Cons(SyntaxLeaf('Name',name),_)):
          StringTools.startsWith(name,'#macro_decl_')
            || StringTools.startsWith(name,'#macro_import_')
            || StringTools.startsWith(name,'#macro_export_');
        case _: false;
      };
      if (erased) continue;
      if (current==index) return form;
      current++;
    }
    return null;
  }

  /** Map an exact structural call path to the corresponding 'expand name'
      pair. Requiring both ordered call lists to agree fails closed on
      unsupported syntax/lowering instead of assigning a guessed offset. */
  static function tracedCallSite(tokens:Array<SourceToken>,area:SourceSpan,
      program:Value,index:Int,callPath:String):Null<SourceSpan> {
    var form=originalFormAt(program,index);
    if (form==null) return null;
    var body:Value=switch(form) {
      case SyntaxNode('Define',Cons(_,Cons(expr,Nil))): expr;
      case SyntaxNode('Evaluate',Cons(expr,Nil)): expr;
      case _: return null;
    };
    var calls:Array<{name:String,path:String}>=[];
    originalMacroCallOrder(body,'',calls);
    var keywords:Array<{name:String,span:SourceSpan}>=[];
    for (i in 0...tokens.length-1) {
      var keyword=tokens[i];
      var named=tokens[i+1];
      if (keyword.text!='expand' || keyword.start<area.start
          || named.end>area.end) continue;
      keywords.push({name:named.text,span:tokenSpan(keyword)});
    }
    if (calls.length!=keywords.length) return null;
    var found:Null<SourceSpan>=null;
    for (i in 0...calls.length) {
      if (calls[i].name!=keywords[i].name) return null;
      if (calls[i].path==callPath) {
        if (found!=null) return null;
        found=keywords[i].span;
      }
    }
    return found;
  }

  /** Convert a single-pass Nail source-path into a real template token.
      The source map itself comes from Nail's NMTrace sidecar. */
  static function tracedMacroNodeOrigin(boot:BootRuntime,traces:Value,
      fault:Value,callerProgram:Value,moduleTable:Value,source:String,
      sourceId:String,modules:Null<String->Null<String>>,
      tokens:Array<SourceToken>):Null<{
        span:SourceSpan,template:Null<SourceSpan>,
        templateOrigin:Null<SourceOrigin>}> {
    var cursor=trail(fault);
    if (cursor==null) return null;
    var areas=sourceForms(tokens);
    if (cursor.index<0 || cursor.index>=areas.length) return null;
    var area=areas[cursor.index];
    var ref=boot.invoke('nmFaultNodeOrigin',SyntaxNode('NMTraceRequest',
      Cons(traces,Cons(fault,Nil))));
    // Nail carries the outermost source call path across nested macros,
    // allowing repeated invocations to be mapped without guessed offsets.
    var site:Null<SourceSpan>=null;
    switch(ref) {
      case SyntaxNode('NMSource',Cons(_,Cons(
          SyntaxLeaf('Name',producer),Cons(_,Cons(
          SyntaxLeaf('Name',callPath),Nil))))) if (producer!='#caller'):
        site=tracedCallSite(tokens,area,callerProgram,cursor.index,callPath);
      case _:
    }
    if (site==null) site=uniqueInForm(tokens,'expand',area);
    // Different macro names in one form retain their safe fallback.
    if (site==null) switch(ref) {
      case SyntaxNode('NMSource',Cons(_,Cons(
          SyntaxLeaf('Name',macroName),_))) if (macroName!='#caller'):
        site=uniqueNamedExpandInForm(tokens,macroName,area);
      case _:
    }
    if (site==null) return null;
    return switch(ref) {
      case SyntaxNode('NMSource',Cons(
          SyntaxLeaf('Name',owner),Cons(
          SyntaxLeaf('Name',macroName),Cons(
          SyntaxLeaf('Name',path),Cons(_,Nil))))) if (macroName!='#caller'):
        var templateProgram=owner=='#caller' ? callerProgram
          : findModuleProgram(moduleTable,owner);
        var templateSource=owner=='#caller' ? source
          : modules==null ? null : modules(owner);
        if (templateProgram==null || templateSource==null) null;
        else {
          var template=templateSyntax(templateProgram,macroName);
          if (template==null) null;
          else {
            var selected=templateAtPath(template,path);
            var message=switch(fault) {
              case SyntaxNode('TCFault',Cons(SyntaxLeaf('TCMessage',text),_)):
                StringTools.trim(text);
              case _: '';
            };
            var pattern=StringTools.startsWith(message,'Non-exhaustive match:')
              || StringTools.startsWith(message,'Mixed constructors in algebraic match')
              || StringTools.startsWith(message,
                'Constructor match binding arity mismatch:');
            var matching=selected==null ? null
              : templateTokenSpan(templateSource,macroName,template,path,
                  selected,pattern ? 'match' : null);
            if (matching==null) null;
            else {
              var ownerId=owner=='#caller' ? sourceId : owner;
              {
                span:site,
                template:ownerId==sourceId ? matching : null,
                templateOrigin:{sourceId:ownerId,span:matching}
              };
            }
          }
        }
      case _: null;
    };
  }

  /** Resolve distinct macros inside one source form by their surface
      invocation names. Duplicate calls to the same macro remain ambiguous. */
  static function uniqueNamedExpandInForm(tokens:Array<SourceToken>,
      macroName:String,area:SourceSpan):Null<SourceSpan> {
    var found:Null<SourceSpan>=null;
    for (i in 0...tokens.length-1) {
      var keyword=tokens[i];
      var name=tokens[i+1];
      if (keyword.start<area.start || name.end>area.end
          || keyword.text!='expand' || name.text!=macroName) continue;
      if (found!=null) return null;
      found=tokenSpan(keyword);
    }
    return found;
  }

  static function templateIdentifier(source:String, macroName:String,
      missing:String):Null<SourceSpan> {
    var tokens=SourcePositions.scan(source);
    var found:Null<SourceSpan>=null;
    var declarations=0;
    for (i in 0...tokens.length-1) {
      if (tokens[i].text != 'macro' || tokens[i+1].text != macroName)
        continue;
      declarations++;
      var depth=0;
      var matching:Null<SourceSpan>=null;
      var duplicates=false;
      for (j in i+2...tokens.length) {
        var word=tokens[j].text;
        if (word=='(' || word=='{' || word=='[') depth++;
        if (word==')' || word=='}' || word==']') depth--;
        if (depth == 0 && word==';') break;
        if (word != missing) continue;
        if (matching != null) duplicates=true;
        matching=tokenSpan(tokens[j]);
      }
      if (duplicates) return null;
      found=matching;
    }
    return declarations == 1 ? found : null;
  }

  /** Nail determines the lexical producer; the scanner only projects the
      symbolic origin to original token offsets. Crucially this path never
      re-invokes the Haxe macro expander for provenance. */
  static function nailMacroOrigin(boot:BootRuntime, program:Value,
      moduleTable:Value, fault:Value, source:String, sourceId:String,
      cachedModules:Null<String->Null<String>>,
      tokens:Array<SourceToken>):Null<{
        span:SourceSpan,template:Null<SourceSpan>,
        templateOrigin:Null<SourceOrigin>}> {
    var position=trail(fault);
    if (position == null) return null;
    var areas=sourceForms(tokens);
    if (position.index < 0 || position.index >= areas.length) return null;
    var site=uniqueInForm(tokens,'expand',areas[position.index]);
    if (site == null) return null;
    var sourceReference=boot.invoke('nmFaultMacroOrigin',
      SyntaxNode('NMOriginRequest',Cons(program,
        Cons(moduleTable,Cons(fault,Nil)))));
    return switch (sourceReference) {
      case SyntaxNode('NMOrigin',Cons(
          SyntaxLeaf('Name',owner),Cons(
          SyntaxLeaf('Name',macroName),Cons(
          SyntaxLeaf('Name',missing),Nil)))):
        var actualId=owner == '#caller' ? sourceId : owner;
        var actualSource=owner == '#caller' ? source
          : cachedModules == null ? null : cachedModules(owner);
        if (actualSource == null) null;
        else {
          var matching=templateIdentifier(actualSource,macroName,missing);
          matching == null ? null : {
            span:site,
            template:actualId == sourceId ? matching : null,
            templateOrigin:{sourceId:actualId,span:matching}
          };
        }
      case _: null;
    };
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

  /** Experimental opt-in entry point for the Nail-written hygienic macro
      expander, including source modules. The regular analyze() continues to
      use the production macro expander unless explicitly requested. */
  public static function analyzeNailMacros(source:String, ?boot:BootRuntime,
      ?modules:String->Null<String>, sourceId:String = '<source>'):NailCheckReport
    return analyze(source,boot,modules,sourceId,true);

  /** Read-only per-source report, using the same Nail bytecode image on Haxe,
      JavaScript and PHP. The optional BootRuntime lets callers reuse the
      compiled source-free image across queries without compiler mutations. */
  public static function analyze(source:String, ?boot:BootRuntime,
      ?modules:String->Null<String>, sourceId:String = '<source>',
      nailMacros:Bool = false):NailCheckReport {
    var runtime = boot == null ? new BootRuntime(60000000) : boot;
    var result:Value;
    var nailProgram:Null<Value>=null;
    var nailModuleTable:Null<Value>=null;
    var nailTraces:Null<Value>=null;
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
      if (nailMacros) {
        // The Nail parser, macro expander and checker exchange only Syntax.
        // Preserve the *actual* input to expansion for symbolic provenance;
        // no host macro replay is needed after a checker fault.
        var prepared=runtime.invoke('tcPrepareTypedSource',Text(source));
        var executable:Value=switch(prepared) {
          case SyntaxNode('TCPreparedMacros',Cons(program,_)): program;
          case _: SyntaxLeaf('MacroError','Typed source preparation failed');
        };
        var moduleTable=NailMacroModuleInputs.collect(
          runtime,source,cachedModules,executable);
        var expandedWithOrigins=runtime.invoke('nailMacroExpandWithModulesTraced',
          NailMacroModuleInputs.request(executable,moduleTable));
        var expanded:Value=switch(expandedWithOrigins) {
          case SyntaxNode('NMExpansionTraced',Cons(result,Cons(traces,Nil))):
            nailTraces=traces;
            result;
          case _: throw 'Unexpected Nail traced macro expansion result';
        };
        nailProgram=executable;
        nailModuleTable=moduleTable;
        result=runtime.invoke('tcCheckExpandedTypedTraced',
          SyntaxNode('TCExpansionRequest',
            Cons(prepared,Cons(expanded,Nil))));
      } else if (cachedModules == null)
        result = runtime.invoke('tcCheckSourceTraced', Text(source));
      else {
        // Preserve typed aliases, relations, annotated definitions and
        // contextual DSL lowering in the Nail parser, NOT the host parser.
        // Only the existing hygienic macro syntax primitive is host-run.
        var prepared = runtime.invoke('tcPrepareTypedSource', Text(source));
        var executable:Value = switch (prepared) {
          case SyntaxNode('TCPreparedMacros',Cons(program,Cons(_,Nil))):
            program;
          case _: SyntaxLeaf('MacroError','Typed source preparation failed');
        };
        var expanded = MacroExpander.syntax(executable, name -> {
          var moduleSource = cachedModules(name);
          if (moduleSource == null) return null;
          MacroModuleDialect.requireCompatible(
            numeric.LanguageVersion.declared(source),
            numeric.NumericDialect.isExact(source), moduleSource, name);
          // Preserve 1 (Int) vs 1.0 (Float) before an AST Syntax round-trip.
          // Both parsing and numeric rewriting happen in Nail bytecode.
          return runtime.invoke('modernRewrite',
            runtime.invoke('parseSource',Text(moduleSource)));
        });
        result = runtime.invoke('tcCheckExpandedTypedTraced',
          SyntaxNode('TCExpansionRequest',
            Cons(prepared,Cons(expanded,Nil))));
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
          var origin=nailMacros && nailProgram != null
              && nailModuleTable != null && nailTraces != null
            ? tracedMacroNodeOrigin(runtime,nailTraces,fault,nailProgram,
                nailModuleTable,source,sourceId,cachedModules,tokens)
            : null;
          if (origin==null && nailMacros && nailProgram!=null
              && nailModuleTable!=null)
            origin=nailMacroOrigin(runtime,nailProgram,nailModuleTable,
              fault,source,sourceId,cachedModules,tokens);
          if (origin==null && !nailMacros)
            origin=macroOrigin(source,fault,lookupMessage,sourceId,cachedModules);
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
