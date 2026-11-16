package nail;

import haxe.ds.StringMap;
import nail.Ast.Expr;
import nail.Ast.Form;
import nail.Value;

/** Strict opt-in hygiene for syntax emitted by Nail procedural transformers.
    New binders MUST use #proc_local_<name>; the marker is alpha-renamed to
    a private, deterministic ID. Ordinary caller variables are left intact.
    This prevents accidental capture of caller syntax without guessing which
    identifiers were introduced by the transformer. */
class ProceduralHygiene {
  static inline var LOCAL = '#proc_local_';
  static inline var PRIVATE = '#proc_gensym_';
  static inline var MAX_NODES = 20000;
  static inline var MAX_DEPTH = 80;

  var serial = 0;
  var steps = 0;

  public static function prepare(generated:Value):Value {
    var instance = new ProceduralHygiene();
    var forms = SyntaxBridge.forms(generated);
    var output:Array<Form> = [];
    for (form in forms) switch (form) {
      case Define(name, body):
        output.push(Define(name, instance.rewrite(body, new StringMap<String>(), 0)));
      case _:
        throw 'Procedural transformer: generated Program may contain only fresh definitions';
    }
    return SyntaxEncoder.program(output);
  }

  /** Recheck an already prepared Program at the public compilation boundary.
      Callers cannot bypass hygiene by passing an arbitrary typed Syntax tree
      directly to ProceduralTransformer.compile. */
  public static function verifyPrepared(generated:Value):Void {
    var instance = new ProceduralHygiene();
    var identities = new StringMap<Bool>();
    for (form in SyntaxBridge.forms(generated)) switch (form) {
      case Define(_, body):
        instance.verifyExpr(body, new StringMap<Bool>(), identities, 0);
      case _:
        throw 'Procedural transformer: generated Program may contain only fresh definitions';
    }
  }

  function verifyExpr(expr:Expr, scope:StringMap<Bool>,
      identities:StringMap<Bool>, depth:Int):Void {
    tick(depth);
    switch (expr) {
      case Literal(_):
      case Var(name):
        if (StringTools.startsWith(name, LOCAL))
          throw 'Procedural transformer: unexpanded local marker ' + name;
        if (StringTools.startsWith(name, PRIVATE) && !scope.exists(name))
          throw 'Procedural transformer: unbound private identifier ' + name;
      case Lambda(name, body):
        if (!~/^#proc_gensym_[0-9]+_[A-Za-z_][A-Za-z_0-9]*$/.match(name))
          throw 'Procedural transformer: generated lambda has no private binder';
        if (identities.exists(name))
          throw 'Procedural transformer: duplicate private binding ' + name;
        identities.set(name, true);
        var nested = new StringMap<Bool>();
        for (key in scope.keys()) nested.set(key, true);
        nested.set(name, true);
        verifyExpr(body, nested, identities, depth + 1);
      case Apply(fn, arg):
        verifyExpr(fn, scope, identities, depth + 1);
        verifyExpr(arg, scope, identities, depth + 1);
      case If(test, yes, no):
        verifyExpr(test, scope, identities, depth + 1);
        verifyExpr(yes, scope, identities, depth + 1);
        verifyExpr(no, scope, identities, depth + 1);
    }
  }

  function new() {}

  function tick(depth:Int):Void {
    if (depth > MAX_DEPTH) throw 'Procedural transformer: syntax nesting limit exceeded';
    if (++steps > MAX_NODES) throw 'Procedural transformer: syntax work limit exceeded';
  }

  function rewrite(expr:Expr, locals:StringMap<String>, depth:Int):Expr {
    tick(depth);
    return switch (expr) {
      case Literal(_): expr;
      case Var(name):
        if (StringTools.startsWith(name, LOCAL)) {
          var resolved = locals.get(name);
          if (resolved == null)
            throw 'Procedural transformer: unbound local marker ' + name;
          Var(resolved);
        } else if (StringTools.startsWith(name, PRIVATE)) {
          throw 'Procedural transformer: private binding cannot be referenced directly';
        } else expr;
      case Lambda(name, body):
        if (!StringTools.startsWith(name, LOCAL)
            || !~/^#proc_local_[A-Za-z_][A-Za-z_0-9]*$/.match(name))
          throw 'Procedural transformer: generated lambda must use a proc-local binder';
        var fresh = PRIVATE + serial++ + '_' + name.substr(LOCAL.length);
        var next = new StringMap<String>();
        for (key in locals.keys()) next.set(key, locals.get(key));
        next.set(name, fresh);
        Lambda(fresh, rewrite(body, next, depth + 1));
      case Apply(fn, arg):
        Apply(rewrite(fn, locals, depth + 1), rewrite(arg, locals, depth + 1));
      case If(test, yes, no):
        If(rewrite(test, locals, depth + 1), rewrite(yes, locals, depth + 1),
          rewrite(no, locals, depth + 1));
    };
  }
}
