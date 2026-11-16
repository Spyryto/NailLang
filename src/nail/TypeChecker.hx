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

  /** Infer/check an AST supplied as first-class Nail Syntax, without reparsing text. */
  public function checkSyntax(tree:Value):Array<String> {
    var solver = new Inference(nextId, global);
    var inferred = solver.run(SyntaxBridge.forms(tree));
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

/** Explicit frame for Hindley-Milner inference. All expression traversal is iterative. */
private class InferFrame {
  public var source:Expr;
  public var scope:StringMap<TypeScheme>;
  public var phase:Int = 0;
  public var saved:NType;
  public function new(source:Expr, scope:StringMap<TypeScheme>) {
    this.source = source;
    this.scope = scope;
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
    var n = TNumber, b = TBoolean, s = TText;
    for (name in ['+', '-', '*', '/']) globals.set(name, mono(fun(n, fun(n, n))));
    for (name in ['<', '<=', '>', '>=']) globals.set(name, mono(fun(n, fun(n, b))));
    globals.set('textLength', mono(fun(s, n)));
    globals.set('textAt', mono(fun(s, fun(n, s))));
    globals.set('textConcat', mono(fun(s, fun(s, s))));
    var tree = TSyntax;
    globals.set('syntaxLeaf', mono(fun(s, fun(s, tree))));
    globals.set('syntaxNode', mono(fun(s, fun(TList(tree), tree))));
    globals.set('syntaxTag', mono(fun(tree, s)));
    globals.set('syntaxText', mono(fun(tree, s)));
    globals.set('syntaxChildren', mono(fun(tree, TList(tree))));
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
    globals.set('#head', poly(fun(list, a), [elem]));
    globals.set('tail', poly(fun(list, list), [elem]));
    globals.set('#tail', poly(fun(list, list), [elem]));
    globals.set('isEmpty', poly(fun(list, b), [elem]));
    globals.set('#isEmpty', poly(fun(list, b), [elem]));
    globals.set('nil', poly(list, [elem]));
  }

  function prune(t:NType):NType {
    var path:Array<Int> = [];
    var current = t;
    var searching = true;
    while (searching) {
      switch (current) {
        case TVariable(id):
          var candidate = substitutions.get(id);
          if (candidate == null) searching = false;
          else { path.push(id); current = candidate; }
        case _: searching = false;
      }
    }
    for (id in path) substitutions.set(id, current);
    return current;
  }

  function occurs(id:Int, ty:NType):Bool {
    var stack:Array<NType> = [ty];
    while (stack.length > 0) {
      switch (prune(stack.pop())) {
        case TVariable(other): if (id == other) return true;
        case TList(a): stack.push(a);
        case TFunction(a, b): stack.push(b); stack.push(a);
        case _:
      }
    }
    return false;
  }

  function requireEquality(ty:NType):Void {
    var stack:Array<NType> = [ty];
    while (stack.length > 0) {
      switch (prune(stack.pop())) {
        case TNumber | TBoolean | TText | TSyntax:
        case TList(a): stack.push(a);
        case TVariable(id): eqRequired.set(id, true);
        case TFunction(_, _): throw 'Type error: functions cannot be compared for equality';
      }
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
    var stack:Array<{a:NType, b:NType}> = [{a:left, b:right}];
    while (stack.length > 0) {
      var pair = stack.pop();
      var a = prune(pair.a), b = prune(pair.b);
      switch ([a, b]) {
        case [TVariable(i), _]: bindVariable(i, b);
        case [_, TVariable(j)]: bindVariable(j, a);
        case [TNumber, TNumber] | [TBoolean, TBoolean] | [TText, TText] | [TSyntax, TSyntax]:
        case [TList(x), TList(y)]: stack.push({a:x, b:y});
        case [TFunction(a1, b1), TFunction(a2, b2)]:
          stack.push({a:b1, b:b2});
          stack.push({a:a1, b:a2});
        case _: throw 'Type error: cannot unify ' + describe(a) + ' with ' + describe(b);
      }
    }
  }

  function replacement(t:NType, mapping:IntMap<NType>):NType {
    var stack:Array<{type:NType, finish:Bool}> = [{type:t, finish:false}];
    var results:Array<NType> = [];
    while (stack.length > 0) {
      var frame = stack.pop();
      if (frame.finish) {
        switch (frame.type) {
          case TList(_): results.push(TList(results.pop()));
          case TFunction(_, _):
            var b = results.pop(), a = results.pop();
            results.push(TFunction(a, b));
          case _: throw 'Invalid type replacement frame';
        }
      } else switch (frame.type) {
        case TVariable(id):
          var current = mapping.get(id);
          results.push(current == null ? frame.type : current);
        case TList(a):
          stack.push({type:frame.type, finish:true});
          stack.push({type:a, finish:false});
        case TFunction(a, b):
          stack.push({type:frame.type, finish:true});
          stack.push({type:b, finish:false});
          stack.push({type:a, finish:false});
        case _: results.push(frame.type);
      }
    }
    return results.pop();
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
    var stack:Array<NType> = [ty];
    while (stack.length > 0) {
      switch (prune(stack.pop())) {
        case TVariable(id): result.set(id, true);
        case TList(item): stack.push(item);
        case TFunction(a, b): stack.push(b); stack.push(a);
        case _:
      }
    }
  }

  function normalize(t:NType):NType {
    var stack:Array<{type:NType, finish:Bool}> = [{type:t, finish:false}];
    var results:Array<NType> = [];
    while (stack.length > 0) {
      var frame = stack.pop();
      if (frame.finish) {
        switch (frame.type) {
          case TList(_): results.push(TList(results.pop()));
          case TFunction(_, _):
            var b = results.pop(), a = results.pop();
            results.push(TFunction(a, b));
          case _: throw 'Invalid type normalization frame';
        }
      } else {
        var normalized = prune(frame.type);
        switch (normalized) {
          case TList(a):
            stack.push({type:normalized, finish:true});
            stack.push({type:a, finish:false});
          case TFunction(a, b):
            stack.push({type:normalized, finish:true});
            stack.push({type:b, finish:false});
            stack.push({type:a, finish:false});
          case _: results.push(normalized);
        }
      }
    }
    return results.pop();
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

  /** Hindley-Milner with explicit expression frames; let generalization stays at
      the direct-lambda application boundary, as in v0.12. */
  function infer(expr:Expr, env:StringMap<TypeScheme>):NType {
    var work:Array<InferFrame> = [new InferFrame(expr, env)];
    var results:Array<NType> = [];
    while (work.length > 0) {
      var frame = work[work.length - 1];
      switch (frame.source) {
        case Literal(Number(_)): results.push(TNumber); work.pop();
        case Literal(Boolean(_)): results.push(TBoolean); work.pop();
        case Literal(Text(_)): results.push(TText); work.pop();
        case Literal(Nil): results.push(TList(fresh())); work.pop();
        case Literal(_): throw 'Type error: unsupported literal';
        case Var(name):
          var scheme = frame.scope.get(name);
          if (scheme == null) throw 'Type error: unknown name ' + name;
          results.push(instantiate(scheme));
          work.pop();
        case Lambda(param, body):
          if (frame.phase == 0) {
            frame.saved = fresh();
            var child = scopeCopy(frame.scope);
            child.set(param, mono(frame.saved));
            frame.phase = 1;
            work.push(new InferFrame(body, child));
          } else {
            var bodyType = results.pop();
            results.push(fun(frame.saved, bodyType));
            work.pop();
          }
        case Apply(Lambda(param, body), argument):
          if (frame.phase == 0) {
            frame.phase = 1;
            work.push(new InferFrame(argument, frame.scope));
          } else if (frame.phase == 1) {
            var boundType = results.pop();
            var child = scopeCopy(frame.scope);
            child.set(param, generalize(boundType, frame.scope));
            frame.phase = 2;
            work.push(new InferFrame(body, child));
          } else work.pop(); // The body's result remains on the value stack.
        case Apply(fn, argument):
          if (frame.phase == 0) {
            frame.phase = 1;
            work.push(new InferFrame(fn, frame.scope));
          } else if (frame.phase == 1) {
            frame.phase = 2;
            work.push(new InferFrame(argument, frame.scope));
          } else {
            var argType = results.pop();
            var fnType = results.pop();
            var ret = fresh();
            unify(fnType, fun(argType, ret));
            results.push(ret);
            work.pop();
          }
        case If(condition, yes, no):
          if (frame.phase == 0) {
            frame.phase = 1;
            work.push(new InferFrame(condition, frame.scope));
          } else if (frame.phase == 1) {
            unify(results.pop(), TBoolean);
            frame.phase = 2;
            work.push(new InferFrame(yes, frame.scope));
          } else if (frame.phase == 2) {
            frame.saved = results.pop();
            frame.phase = 3;
            work.push(new InferFrame(no, frame.scope));
          } else {
            unify(frame.saved, results.pop());
            results.push(frame.saved);
            work.pop();
          }
      }
    }
    if (results.length != 1) throw 'Type error: invalid inference result';
    return results.pop();
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
    var output = new StringBuf();
    var stack:Array<{type:NType, text:String, parens:Bool}> = [{type:ty, text:null, parens:false}];
    while (stack.length > 0) {
      var frame = stack.pop();
      if (frame.text != null) {
        output.add(frame.text);
        continue;
      }
      switch (prune(frame.type)) {
        case TNumber: output.add('Number');
        case TBoolean: output.add('Bool');
        case TText: output.add('Text');
        case TSyntax: output.add('Syntax');
        case TVariable(id): output.add(label(id));
        case TList(item):
          stack.push({type:null, text:']', parens:false});
          stack.push({type:item, text:null, parens:false});
          stack.push({type:null, text:'[', parens:false});
        case TFunction(a, b):
          if (frame.parens) stack.push({type:null, text:')', parens:false});
          stack.push({type:b, text:null, parens:false});
          stack.push({type:null, text:' -> ', parens:false});
          stack.push({type:a, text:null, parens:true});
          if (frame.parens) stack.push({type:null, text:'(', parens:false});
      }
    }
    var result = output.toString();
    return eq.length == 0 ? result : 'Eq ' + eq.join(', ') + ' => ' + result;
  }
}
