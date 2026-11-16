package nail;

import haxe.ds.IntMap;
import haxe.ds.StringMap;
import nail.Ast.Expr;
import nail.Ast.Form;
import nail.NType;
import nail.Value;

/** Hindley–Milner type inference over the existing five-node AST.
    - Eager application and lexical lambda bindings.
    - Generalization at top-level `def` (let-polymorphism).
    - Monomorphic self-reference while inferring a recursive definition.
    - Equality constraints: only Number, Boolean and lists thereof are Eq.
    - Checking is transactional with respect to the type environment.
 */
class TypeChecker {
  var global:StringMap<TypeScheme>;
  var nextId:Int;

  public function new() {
    var solver = new Inference(0, new StringMap<TypeScheme>());
    solver.installPrimitives();
    global = solver.globals;
    nextId = solver.nextId;
  }

  /** Return the types of top-level expressions; definitions also get inferred. */
  public function check(source:String):Array<String> {
    var forms = new Parser(source).parse();
    var solver = new Inference(nextId, global);
    var inferred = solver.run(forms);
    // Commit only after the whole type-check succeeds.
    global = solver.globals;
    nextId = solver.nextId;
    return inferred;
  }

  /** No mutation of this checker: useful for IDEs and preflight checks. */
  public function preview(source:String):Array<String> return copy().check(source);

  public function copy():TypeChecker {
    var instance = new TypeChecker();
    instance.global = new StringMap<TypeScheme>();
    for (name in global.keys()) instance.global.set(name, global.get(name));
    instance.nextId = nextId;
    return instance;
  }

  /** Print a polymorphic definition's inferred signature (e.g. a -> a). */
  public function signature(name:String):String {
    return new Inference(nextId, global).signature(name);
  }

  public function names():Array<String> {
    var result:Array<String> = [];
    for (name in global.keys()) if (!StringTools.startsWith(name, '#')) result.push(name);
    result.sort(Reflect.compare);
    return result;
  }
}

/** Per-call unifier and program checker. It only mutates its private copy of globals. */
private class Inference {
  public var globals(default, null):StringMap<TypeScheme>;
  public var nextId(default, null):Int;
  final substitutions:IntMap<NType> = new IntMap<NType>();
  final eqRequired:IntMap<Bool> = new IntMap<Bool>();

  public function new(start:Int, initial:StringMap<TypeScheme>) {
    nextId = start;
    globals = new StringMap<TypeScheme>();
    for (name in initial.keys()) globals.set(name, initial.get(name));
  }

  function fresh():NType return TVariable(nextId++);

  static function fun(a:NType, b:NType):NType return TFunction(a, b);
  static function mono(t:NType):TypeScheme return {term:t, quantified:[], comparable:[]};
  static function poly(t:NType, quantified:Array<Int>, comparable:Array<Int> = null):TypeScheme {
    return {term:t, quantified:quantified, comparable:comparable == null ? [] : comparable};
  }

  public function installPrimitives():Void {
    var n = TNumber, b = TBoolean;
    for (name in ['+', '-', '*', '/']) globals.set(name, mono(fun(n, fun(n, n))));
    for (name in ['<', '<=', '>', '>=']) globals.set(name, mono(fun(n, fun(n, b))));
    for (name in ['==', '!=']) {
      var id = nextId++;
      var a = TVariable(id);
      globals.set(name, poly(fun(a, fun(a, b)), [id], [id]));
    }
    var elem = nextId++;
    var a = TVariable(elem);
    var list = TList(a);
    globals.set('cons', poly(fun(a, fun(list, list)), [elem]));
    globals.set('#cons', poly(fun(a, fun(list, list)), [elem]));
    globals.set('head', poly(fun(list, a), [elem]));
    globals.set('tail', poly(fun(list, list), [elem]));
    globals.set('isEmpty', poly(fun(list, b), [elem]));
    globals.set('nil', poly(list, [elem]));
  }

  function prune(t:NType):NType {
    return switch (t) {
      case TVariable(i):
        var v = substitutions.get(i);
        if (v == null) t else {
          var normalized = prune(v);
          substitutions.set(i, normalized);
          normalized;
        }
      case _: t;
    };
  }

  function occurs(id:Int, ty:NType):Bool {
    return switch (prune(ty)) {
      case TVariable(other): id == other;
      case TList(a): occurs(id, a);
      case TFunction(a, b): occurs(id, a) || occurs(id, b);
      case _: false;
    };
  }

  function requireEquality(ty:NType):Void {
    switch (prune(ty)) {
      case TNumber | TBoolean:
      case TList(a): requireEquality(a);
      case TVariable(id): eqRequired.set(id, true);
      case TFunction(_, _): throw 'Type error: functions cannot be compared for equality';
    }
  }

  function bindVariable(id:Int, ty:NType):Void {
    var normalized = prune(ty);
    switch (normalized) {
      case TVariable(other) if (other == id): return;
      case _:
    }
    if (occurs(id, normalized)) throw 'Type error: infinite type (occurs check)';
    if (eqRequired.exists(id)) requireEquality(normalized);
    substitutions.set(id, normalized);
  }

  function unify(left:NType, right:NType):Void {
    var a = prune(left), b = prune(right);
    switch ([a, b]) {
      case [TVariable(i), _]: bindVariable(i, b);
      case [_, TVariable(j)]: bindVariable(j, a);
      case [TNumber, TNumber] | [TBoolean, TBoolean]:
      case [TList(x), TList(y)]: unify(x, y);
      case [TFunction(a1, b1), TFunction(a2, b2)]: unify(a1, a2); unify(b1, b2);
      case _: throw 'Type error: cannot unify ' + describe(a) + ' with ' + describe(b);
    }
  }

  function replacement(t:NType, mapping:IntMap<NType>):NType {
    return switch (t) {
      case TVariable(id):
        var current = mapping.get(id);
        current == null ? t : current;
      case TList(a): TList(replacement(a, mapping));
      case TFunction(a, b): TFunction(replacement(a, mapping), replacement(b, mapping));
      case _: t;
    };
  }

  function instantiate(scheme:TypeScheme):NType {
    var replacements = new IntMap<NType>();
    for (id in scheme.quantified) replacements.set(id, fresh());
    for (id in scheme.comparable) {
      var target = replacements.get(id);
      requireEquality(target == null ? TVariable(id) : target);
    }
    return replacement(scheme.term, replacements);
  }

  function free(ty:NType, result:IntMap<Bool>):Void {
    switch (prune(ty)) {
      case TVariable(id): result.set(id, true);
      case TList(t): free(t, result);
      case TFunction(a, b): free(a, result); free(b, result);
      case _:
    }
  }

  function normalize(t:NType):NType {
    return switch (prune(t)) {
      case TList(a): TList(normalize(a));
      case TFunction(a, b): TFunction(normalize(a), normalize(b));
      case other: other;
    };
  }

  function generalize(t:NType, env:StringMap<TypeScheme>):TypeScheme {
    t = normalize(t);
    var candidates = new IntMap<Bool>();
    free(t, candidates);
    var bound = new IntMap<Bool>();
    for (scheme in env) {
      var vars = new IntMap<Bool>();
      free(scheme.term, vars);
      for (id in scheme.quantified) vars.remove(id);
      for (id in vars.keys()) bound.set(id, true);
    }
    var quantified:Array<Int> = [];
    var comparable:Array<Int> = [];
    for (id in candidates.keys()) if (!bound.exists(id)) {
      quantified.push(id);
      if (eqRequired.exists(id)) comparable.push(id);
    }
    quantified.sort((a, b) -> a - b);
    comparable.sort((a, b) -> a - b);
    return poly(t, quantified, comparable);
  }

  static function scopeCopy(env:StringMap<TypeScheme>):StringMap<TypeScheme> {
    var output = new StringMap<TypeScheme>();
    for (key in env.keys()) output.set(key, env.get(key));
    return output;
  }

  function infer(expr:Expr, env:StringMap<TypeScheme>):NType {
    return switch (expr) {
      case Literal(Number(_)): TNumber;
      case Literal(Boolean(_)): TBoolean;
      case Literal(Nil): TList(fresh());
      case Literal(_): throw 'Type error: unsupported literal';
      case Var(name):
        var scheme = env.get(name);
        if (scheme == null) throw 'Type error: unknown name ' + name;
        instantiate(scheme);
      case Lambda(param, body):
        var arg = fresh();
        var child = scopeCopy(env);
        child.set(param, mono(arg));
        fun(arg, infer(body, child));
      case Apply(f, x):
        var fn = infer(f, env);
        var argument = infer(x, env);
        var result = fresh();
        unify(fn, fun(argument, result));
        result;
      case If(condition, yes, no):
        unify(infer(condition, env), TBoolean);
        var a = infer(yes, env);
        var b = infer(no, env);
        unify(a, b);
        a;
    };
  }

  public function run(forms:Array<Form>):Array<String> {
    var inferred:Array<NType> = [];
    for (form in forms) switch (form) {
      case Define(name, expr):
        if (globals.exists(name)) throw 'Type error: already defined ' + name;
        // Recursive name is monomorphic during inference; generalized afterwards.
        var provisional = fresh();
        var env = scopeCopy(globals);
        env.set(name, mono(provisional));
        var t = infer(expr, env);
        unify(provisional, t);
        globals.set(name, generalize(t, globals));
      case Evaluate(expr): inferred.push(infer(expr, globals));
    }
    return [for (t in inferred) describe(t)];
  }

  public function signature(name:String):String {
    var scheme = globals.get(name);
    if (scheme == null) throw 'Type error: unknown name ' + name;
    return describe(instantiate(scheme));
  }

  function describe(ty:NType):String {
    var vars = new IntMap<String>();
    var eq:Array<String> = [];
    var count = 0;
    function label(id:Int):String {
      var name = vars.get(id);
      if (name != null) return name;
      var index = count++;
      var base = String.fromCharCode(97 + (index % 26));
      name = index < 26 ? base : base + Std.string(Std.int(index / 26));
      vars.set(id, name);
      if (eqRequired.exists(id)) eq.push(name);
      return name;
    }
    function write(t:NType, parenthesize:Bool):String {
      return switch (prune(t)) {
        case TNumber: 'Number';
        case TBoolean: 'Bool';
        case TVariable(id): label(id);
        case TList(item): '[' + write(item, false) + ']';
        case TFunction(a, b):
          var text = write(a, true) + ' -> ' + write(b, false);
          parenthesize ? '(' + text + ')' : text;
      };
    }
    var result = write(ty, false);
    return eq.length == 0 ? result : 'Eq ' + eq.join(', ') + ' => ' + result;
  }
}
