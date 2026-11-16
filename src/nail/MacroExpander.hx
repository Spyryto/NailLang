package nail;

import haxe.ds.StringMap;
import nail.Ast.Expr;
import nail.Ast.Form;

private typedef MacroDefinition = {
  var name:String;
  var params:Array<String>;
  var template:Expr;
  var scope:StringMap<MacroDefinition>;
}

/** Expansion works on core-shaped trees. Macro markers exist only between
    parsing and expansion and never become bytecode instructions. */
class MacroExpander {
  public static inline var DECL = '#macro_decl_';
  public static inline var IMPORT = '#macro_import_';
  public static inline var EXPORT = '#macro_export_';
  public static inline var GLOBAL = '#macro_global_';
  static inline var QUOTE = '#macro_quote';
  static inline var UNQUOTE = '#macro_unquote';
  static inline var EXPAND = '#macro_expand';
  static inline var FRESH = '#macro_local_';
  static inline var MAX_DEPTH = 128;
  static inline var MAX_NODES = 1000000;

  var serial = 0;
  var visited = 0;
  final resolve:Null<String->Value>;
  final loaded = new StringMap<StringMap<MacroDefinition>>();
  final loading:Array<String> = [];

  public static function globalName(name:String):String {
    return StringTools.startsWith(name, GLOBAL) ? name.substr(GLOBAL.length) : name;
  }

  public static function forms(input:Array<Form>):Array<Form> {
    return new MacroExpander(null).unit(input, null);
  }

  function unit(input:Array<Form>, exports:Null<StringMap<MacroDefinition>>):Array<Form> {
    var scope = new StringMap<MacroDefinition>();
    var own = new StringMap<Bool>();
    var output:Array<Form> = [];
    for (form in input) switch (form) {
      case Define(name, body) if (StringTools.startsWith(name, IMPORT)):
        var label = name.substr(IMPORT.length);
        if (scope.exists(label)) fail('duplicate macro ' + label);
        switch (body) {
          case Var(moduleName):
            var definition = moduleExports(moduleName).get(label);
            if (definition == null) fail('macro ' + label + ' is not exported by ' + moduleName);
            scope.set(label, definition);
          case _: fail('invalid macro import ' + label);
        }
      case Define(name, _) if (StringTools.startsWith(name, EXPORT)):
        var label = name.substr(EXPORT.length);
        if (exports == null) fail('export is only allowed in a macro module');
        if (!own.exists(label)) fail('export requires a local macro already declared: ' + label);
        if (exports.exists(label)) fail('duplicate export ' + label);
        exports.set(label, scope.get(label));
      case Define(name, body) if (StringTools.startsWith(name, DECL)):
        var label = name.substr(DECL.length);
        if (!~/^[A-Za-z_][A-Za-z_0-9]*$/.match(label)) fail('invalid macro name ' + label);
        if (scope.exists(label)) fail('duplicate macro ' + label);
        var parameters:Array<String> = [];
        var cursor = body;
        while (true) switch (cursor) {
          case Lambda(param, next):
            if (parameters.indexOf(param) >= 0) fail('duplicate macro parameter ' + param);
            parameters.push(param);
            cursor = next;
          case _: break;
        }
        var template = switch (cursor) {
          case Apply(Var(QUOTE), expr): expr;
          case _: fail('expected quote ( expression ) in ' + label);
        };
        var lexical = scope.copy();
        var definition = {name:label, params:parameters, template:template, scope:lexical};
        validate(template, definition, 0);
        own.set(label, true);
        scope.set(label, definition);
        lexical.set(label, definition);
      case _ if (exports != null):
        fail('only macro declarations, imports and exports are allowed in a macro module');
      case Define(name, body):
        output.push(Define(name, expand(body, scope)));
      case Evaluate(body):
        output.push(Evaluate(expand(body, scope)));
      case _:
        output.push(form);
    }
    return output;
  }

  /** Return the original nodes for marker-free programs so literal spellings
      survive bootstrap. Only the forms that contain macros are re-encoded. */
  public static function syntax(tree:Value, ?resolve:String->Value):Value {
    switch (tree) {
      case SyntaxLeaf('MacroError', _): return tree;
      case SyntaxNode('Program', _):
      case _: return tree;
    }
    if (!hasSyntaxMarkers(tree)) return tree;
    try {
      var input = SyntaxBridge.forms(tree);
      var expanded = new MacroExpander(resolve).unit(input, null);
      var output:Array<Value> = [];
      var index = 0;
      var outputIndex = 0;
      var rest = switch (tree) {
        case SyntaxNode(_, children): children;
        case _: throw 'Expected Program';
      };
      while (true) switch (rest) {
        case Cons(raw, tail):
          rest = tail;
          switch (input[index++]) {
            case Define(name, _) if (directive(name)):
            case form:
              var normalized = expanded[outputIndex++];
              output.push(form == normalized ? raw : SyntaxEncoder.form(normalized));
          }
        case Nil: break;
        case _: throw 'Expected Program forms';
      }
      var list:Value = Nil;
      var i = output.length;
      while (i > 0) list = Cons(output[--i], list);
      return SyntaxNode('Program', list);
    } catch (error:MacroExpansionError) {
      return SyntaxLeaf('MacroError', error.reason);
    }
  }

  static function hasSyntaxMarkers(tree:Value):Bool {
    var stack = [tree];
    while (stack.length > 0) switch (stack.pop()) {
      case SyntaxLeaf('Name', name) if (directive(name)): return true;
      case SyntaxLeaf('Var', name) if (marker(name)): return true;
      case SyntaxNode(_, items): stack.push(items);
      case Cons(a, b): stack.push(a); stack.push(b);
      case _:
    }
    return false;
  }

  static function directive(name:String):Bool {
    return StringTools.startsWith(name, DECL) || StringTools.startsWith(name, IMPORT)
      || StringTools.startsWith(name, EXPORT);
  }

  function moduleExports(name:String):StringMap<MacroDefinition> {
    if (!~/^[A-Za-z_][A-Za-z_0-9]*$/.match(name)) return fail('invalid macro module name ' + name);
    if (resolve == null) return fail('macro module ' + name + ' requires a module resolver');
    if (loaded.exists(name)) return loaded.get(name);
    if (loading.indexOf(name) >= 0) return fail('cyclic macro imports: ' + loading.concat([name]).join(' -> '));
    if (loading.length >= MAX_DEPTH) return fail('macro import nesting limit exceeded');
    var source = resolve(name);
    if (source == null) return fail('missing macro module ' + name);
    loading.push(name);
    var exports = new StringMap<MacroDefinition>();
    unit(SyntaxBridge.forms(source), exports);
    loading.pop();
    loaded.set(name, exports);
    return exports;
  }

  static function marker(name:String):Bool return name == QUOTE || name == UNQUOTE || name == EXPAND;

  static function fail(message:String):Dynamic throw new MacroExpansionError(message);

  function new(resolve:Null<String->Value>) this.resolve = resolve;

  function tick(depth:Int):Void {
    if (depth > MAX_DEPTH) fail('expansion nesting limit exceeded');
    if (++visited > MAX_NODES) fail('expansion work limit exceeded');
  }

  /** Validate holes even when the declared macro is never used. */
  function validate(expr:Expr, definition:MacroDefinition, depth:Int):Void {
    tick(depth);
    switch (expr) {
      case Apply(Var(UNQUOTE), Var(name)):
        if (definition.params.indexOf(name) < 0) fail('unknown unquote parameter ' + name + ' in ' + definition.name);
      case Apply(Var(UNQUOTE), _): fail('unquote expects a parameter name');
      case Var(UNQUOTE): fail('unquote expects a parameter name');
      case Var(QUOTE): fail('nested quote is not supported');
      case Apply(fn, arg): validate(fn, definition, depth + 1); validate(arg, definition, depth + 1);
      case Lambda(_, body): validate(body, definition, depth + 1);
      case If(test, yes, no):
        validate(test, definition, depth + 1);
        validate(yes, definition, depth + 1);
        validate(no, definition, depth + 1);
      case _:
    }
  }

  static function hasMarkers(expr:Expr):Bool {
    var stack = [expr];
    while (stack.length > 0) switch (stack.pop()) {
      case Var(name) if (marker(name)): return true;
      case Lambda(_, body): stack.push(body);
      case Apply(fn, arg): stack.push(fn); stack.push(arg);
      case If(test, yes, no): stack.push(test); stack.push(yes); stack.push(no);
      case _:
    }
    return false;
  }

  function expand(expr:Expr, scope:StringMap<MacroDefinition>):Expr {
    return hasMarkers(expr) ? walk(expr, scope, null, null, 0) : expr;
  }

  /** Template and caller subtrees are walked in their own scopes. The caller
      arguments are fully expanded before insertion and are never renamed. */
  function walk(expr:Expr, scope:StringMap<MacroDefinition>, holes:Null<StringMap<Expr>>,
      locals:Null<StringMap<String>>, depth:Int):Expr {
    tick(depth);
    switch (expr) {
      case Apply(Var(UNQUOTE), Var(name)) if (holes != null):
        if (!holes.exists(name)) return fail('unknown unquote parameter ' + name);
        return holes.get(name);
      case Apply(_, _):
        var call = invocation(expr);
        if (call != null) {
          var definition = scope.get(call.name);
          if (definition == null) return fail('unknown macro ' + call.name);
          if (call.args.length < definition.params.length) return fail('macro ' + call.name + ' expects '
            + definition.params.length + ' arguments, got ' + call.args.length);
          var bindings = new StringMap<Expr>();
          for (i in 0...definition.params.length)
            bindings.set(definition.params[i], walk(call.args[i], scope, holes, locals, depth + 1));
          var result = walk(definition.template, definition.scope, bindings, new StringMap<String>(), depth + 1);
          for (i in definition.params.length...call.args.length)
            result = Apply(result, walk(call.args[i], scope, holes, locals, depth + 1));
          return result;
        }
        switch (expr) {
          case Apply(fn, arg):
            return Apply(walk(fn, scope, holes, locals, depth + 1), walk(arg, scope, holes, locals, depth + 1));
          case _: return fail('invalid application');
        }
      case Lambda(name, body):
        if (locals == null) return Lambda(name, walk(body, scope, holes, null, depth + 1));
        var fresh = FRESH + serial++ + '_' + name;
        var previous = locals.get(name);
        locals.set(name, fresh);
        var expanded = walk(body, scope, holes, locals, depth + 1);
        if (previous == null) locals.remove(name); else locals.set(name, previous);
        return Lambda(fresh, expanded);
      case If(test, yes, no):
        return If(walk(test, scope, holes, locals, depth + 1), walk(yes, scope, holes, locals, depth + 1),
          walk(no, scope, holes, locals, depth + 1));
      case Var(name):
        if (marker(name)) return fail(switch (name) {
          case QUOTE: 'quote belongs at the start of a macro body';
          case UNQUOTE: 'unquote belongs inside a macro template';
          case _: 'expand expects a macro name';
        });
        if (locals == null) return expr;
        var binding = locals.get(name);
        return Var(binding != null ? binding : GLOBAL + name);
      case Literal(_): return expr;
    }
  }

  static function invocation(expr:Expr):Null<{name:String, args:Array<Expr>}> {
    var arguments:Array<Expr> = [];
    var current = expr;
    while (true) switch (current) {
      case Apply(Var(EXPAND), Var(name)):
        arguments.reverse();
        return {name:name, args:arguments};
      case Apply(Var(EXPAND), _): return fail('expand expects a macro name');
      case Apply(fn, arg): arguments.push(arg); current = fn;
      case _: return null;
    }
  }
}

private class MacroExpansionError extends haxe.Exception {
  public final reason:String;

  public function new(reason:String) {
    super('Macro error: ' + reason);
    this.reason = reason;
  }
}
