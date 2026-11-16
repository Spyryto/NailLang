package nail;

import haxe.ds.ObjectMap;
import haxe.ds.StringMap;
import nail.Ast.Expr;
import nail.Ast.Form;
import nail.SourcePositions.SourceSpan;

/** Stable within one resolved program; numeric IDs never enter executable code. */
typedef BindingIdentity = {
  final id:Int;
  final name:String;
  final kind:String;
  final source:Null<SourceSpan>;
}

typedef VariableReference = {
  final name:String;
  final target:Null<BindingIdentity>;
}

private typedef LexicalScope = {
  final symbol:BindingIdentity;
  final parent:Null<LexicalScope>;
}

private typedef BindingWork = {
  final node:Expr;
  final scope:Null<LexicalScope>;
}

/** Resolve lexical and top-level bindings by identity, without renaming or
    modifying the five-form expression AST. Generated hygienic names resolve
    just like any other lexical binder; #macro_global_ explicitly bypasses
    local scopes. Free host primitives intentionally retain a null target.
    Use on one post-expansion Program: it does not expand macros itself. */
class BindingAnalysis {
  public final declarations:ObjectMap<Dynamic, BindingIdentity> = new ObjectMap();
  public final parameters:ObjectMap<Dynamic, BindingIdentity> = new ObjectMap();
  public final references:ObjectMap<Dynamic, VariableReference> = new ObjectMap();
  public final symbols:Array<BindingIdentity> = [];

  final globals:StringMap<BindingIdentity> = new StringMap();
  final provenance:Null<SourceProvenance>;

  function new(provenance:Null<SourceProvenance>) {
    this.provenance = provenance;
  }

  function declare(name:String, kind:String, source:Null<SourceSpan>):BindingIdentity {
    var symbol:BindingIdentity = {id:symbols.length, name:name, kind:kind, source:source};
    symbols.push(symbol);
    return symbol;
  }

  function find(name:String, scope:Null<LexicalScope>):Null<BindingIdentity> {
    if (StringTools.startsWith(name, MacroExpander.GLOBAL))
      return globals.get(name.substr(MacroExpander.GLOBAL.length));
    var cursor = scope;
    while (cursor != null) {
      if (cursor.symbol.name == name) return cursor.symbol;
      cursor = cursor.parent;
    }
    return globals.get(name);
  }

  /** Iterative traversal: deep application trees do not consume host stack. */
  function walk(root:Expr):Void {
    var work:Array<BindingWork> = [{node:root,scope:null}];
    while (work.length > 0) {
      var item = work.pop();
      switch (item.node) {
        case Literal(_):
        case Var(name):
          references.set(item.node, {name:name,target:find(name,item.scope)});
        case Lambda(param, body):
          var span = provenance == null ? null : provenance.spanOfExpression(item.node);
          var symbol = declare(param, 'parameter', span);
          parameters.set(item.node, symbol);
          work.push({node:body, scope:{symbol:symbol,parent:item.scope}});
        case Apply(fn, argument):
          work.push({node:argument,scope:item.scope});
          work.push({node:fn,scope:item.scope});
        case If(test, yes, no):
          work.push({node:no,scope:item.scope});
          work.push({node:yes,scope:item.scope});
          work.push({node:test,scope:item.scope});
      }
    }
  }

  public static function resolve(forms:Array<Form>, ?provenance:SourceProvenance):BindingAnalysis {
    var result = new BindingAnalysis(provenance);
    for (form in forms) {
      switch (form) {
        case Define(name, body):
          var span = provenance == null ? null : provenance.spanOfForm(form);
          var symbol = result.declare(name, 'definition', span);
          result.declarations.set(form, symbol);
          // The current definition is visible within its own body.
          result.globals.set(name, symbol);
          result.walk(body);
        case Evaluate(body): result.walk(body);
        case RecordType(_, _, _) | SumType(_, _, _):
          // Type and constructor namespaces are checked separately.
      }
    }
    return result;
  }

  public function bindingForVariable(expr:Expr):Null<BindingIdentity> {
    var reference = references.get(expr);
    return reference == null ? null : reference.target;
  }

  public function bindingForParameter(expr:Expr):Null<BindingIdentity>
    return parameters.get(expr);

  public function bindingForDefinition(form:Form):Null<BindingIdentity>
    return declarations.get(form);
}
