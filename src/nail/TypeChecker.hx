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
  var records:StringMap<Bool>;
  var sums:StringMap<Int>;
  var sumCases:StringMap<Array<{name:String, arity:Int}>>;
  var constructorOwners:StringMap<String>;
  var nextId:Int;

  public function new() {
    var solver = new Inference(0, new StringMap<TypeScheme>(), new StringMap<Bool>(), new StringMap<Int>(),
      new StringMap<Array<{name:String, arity:Int}>>(), new StringMap<String>());
    solver.installPrimitives();
    global = solver.globals;
    records = solver.records;
    sums = solver.sums;
    sumCases = solver.sumCases;
    constructorOwners = solver.constructorOwners;
    nextId = solver.nextId;
  }

  /** Return the types of top-level expressions; definitions also get inferred. */
  public function check(source:String, ?modules:String->Null<String>):Array<String> {
    var forms = new Parser(source).parse(modules);
    var solver = new Inference(nextId, global, records, sums, sumCases, constructorOwners);
    var inferred = solver.run(forms);
    // Commit only after the whole type-check succeeds.
    global = solver.globals;
    records = solver.records;
    sums = solver.sums;
    sumCases = solver.sumCases;
    constructorOwners = solver.constructorOwners;
    nextId = solver.nextId;
    return inferred;
  }

  /** Infer/check an AST supplied as first-class Nail Syntax, without reparsing text. */
  public function checkSyntax(tree:Value):Array<String> {
    var solver = new Inference(nextId, global, records, sums, sumCases, constructorOwners);
    var inferred = solver.run(SyntaxBridge.forms(MacroExpander.syntax(tree)));
    global = solver.globals;
    records = solver.records;
    sums = solver.sums;
    sumCases = solver.sumCases;
    constructorOwners = solver.constructorOwners;
    nextId = solver.nextId;
    return inferred;
  }

  /** Check a generated Program against explicit, closed monomorphic types.
      The source Program supplies the nominal type environment; generated
      definitions must have fresh names and the same order as contracts.
      Transactional: this TypeChecker is not mutated by success or failure.
      This is a host-side API, not public procedural macro registration. */
  public function checkGenerated(source:Value, generated:Value,
      contracts:Array<{name:String, type:NType}>):Array<String> {
    var sourceChecker = copy();
    sourceChecker.checkSyntax(source);
    var solver = new Inference(sourceChecker.nextId, sourceChecker.global,
      sourceChecker.records, sourceChecker.sums, sourceChecker.sumCases,
      sourceChecker.constructorOwners);
    return solver.verifyGenerated(SyntaxBridge.forms(generated), contracts);
  }

  /** A separately compiled module may refer only to explicitly imported
      monomorphic symbols. The caller provides an already verified interface
      (not an inferred or arbitrary polymorphic promise). */
  public function importSignature(name:String, type:NType):Void {
    if (!~/^[A-Za-z_][A-Za-z_0-9]*$/.match(name))
      throw 'Module type error: invalid import alias ' + name;
    if (global.exists(name))
      throw 'Module type error: duplicate or reserved import alias ' + name;
    var pending:Array<NType> = [type];
    while (pending.length > 0) switch (pending.pop()) {
      case TNumber | TExact | TBoolean | TText | TSyntax:
      case TList(child) | TVector(child): pending.push(child);
      case TFunction(a, b): pending.push(b); pending.push(a);
      case TVariable(_):
        throw 'Module type error: polymorphic import signatures are not yet supported';
      case TRecord(_) | TSum(_, _):
        throw 'Module type error: cross-module nominal types require public interfaces';
    }
    global.set(name, {term:type, quantified:[], comparable:[]});
  }

  /** No mutation of this checker: useful for IDEs and preflight checks. */
  public function preview(source:String, ?modules:String->Null<String>):Array<String>
    return copy().check(source, modules);

  public function copy():TypeChecker {
    var instance = new TypeChecker();
    instance.global = new StringMap<TypeScheme>();
    for (name in global.keys()) instance.global.set(name, global.get(name));
    instance.records = new StringMap<Bool>();
    for (name in records.keys()) instance.records.set(name, true);
    instance.sums = new StringMap<Int>();
    for (name in sums.keys()) instance.sums.set(name, sums.get(name));
    instance.sumCases = new StringMap<Array<{name:String, arity:Int}>>();
    for (name in sumCases.keys()) instance.sumCases.set(name, sumCases.get(name).copy());
    instance.constructorOwners = new StringMap<String>();
    for (name in constructorOwners.keys()) instance.constructorOwners.set(name, constructorOwners.get(name));
    instance.nextId = nextId;
    return instance;
  }

  /** Print a polymorphic definition's inferred signature (e.g. a -> a). */
  public function signature(name:String):String {
    return new Inference(nextId, global, records, sums, sumCases, constructorOwners).signature(name);
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
  public var records(default, null):StringMap<Bool>;
  public var sums(default, null):StringMap<Int>;
  public var sumCases(default, null):StringMap<Array<{name:String, arity:Int}>>;
  public var constructorOwners(default, null):StringMap<String>;
  public var nextId(default, null):Int;
  final substitutions:IntMap<NType> = new IntMap<NType>();
  final eqRequired:IntMap<Bool> = new IntMap<Bool>();

  public function new(start:Int, initial:StringMap<TypeScheme>, knownRecords:StringMap<Bool>,
      knownSums:StringMap<Int>, knownCases:StringMap<Array<{name:String, arity:Int}>>,
      knownOwners:StringMap<String>) {
    nextId = start;
    globals = new StringMap<TypeScheme>();
    for (name in initial.keys()) globals.set(name, initial.get(name));
    records = new StringMap<Bool>();
    for (name in knownRecords.keys()) records.set(name, true);
    sums = new StringMap<Int>();
    for (name in knownSums.keys()) sums.set(name, knownSums.get(name));
    sumCases = new StringMap<Array<{name:String, arity:Int}>>();
    for (name in knownCases.keys()) sumCases.set(name, knownCases.get(name).copy());
    constructorOwners = new StringMap<String>();
    for (name in knownOwners.keys()) constructorOwners.set(name, knownOwners.get(name));
  }

  function fresh():NType return TVariable(nextId++);

  static function fun(a:NType, b:NType):NType return TFunction(a, b);
  static function mono(t:NType):TypeScheme return {term:t, quantified:[], comparable:[]};
  static function poly(t:NType, quantified:Array<Int>, comparable:Array<Int> = null):TypeScheme {
    return {term:t, quantified:quantified, comparable:comparable == null ? [] : comparable};
  }

  public function installPrimitives():Void {
    var n = TNumber, e = TExact, b = TBoolean, s = TText;
    for (name in ['+', '-', '*', '/']) globals.set('#exact' + name, mono(fun(e, fun(e, e))));
    for (name in ['<', '<=', '>', '>=']) globals.set('#exact' + name, mono(fun(e, fun(e, b))));
    globals.set('#exactEncode', mono(fun(s, s)));
    globals.set('exactEncode', mono(fun(s, s)));
    globals.set('exactFromText', mono(fun(s, e)));
    globals.set('exactToFloat', mono(fun(e, n)));
    globals.set('textLengthExact', mono(fun(s, e)));
    globals.set('textAtExact', mono(fun(s, fun(e, s))));
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
    globals.set('macroExpandSyntax', mono(fun(tree, tree)));
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
    var vector = TVector(a);
    globals.set('vector', poly(fun(list, vector), [elem]));
    globals.set('vectorLength', poly(fun(vector, n), [elem]));
    globals.set('vectorGet', poly(fun(vector, fun(n, a)), [elem]));
    globals.set('vectorSet', poly(fun(vector, fun(n, fun(a, vector))), [elem]));
    globals.set('vectorLengthExact', poly(fun(vector, e), [elem]));
    globals.set('vectorGetExact', poly(fun(vector, fun(e, a)), [elem]));
    globals.set('vectorSetExact', poly(fun(vector, fun(e, fun(a, vector))), [elem]));
    globals.set('nil', poly(list, [elem]));
    var x = nextId++, y = nextId++;
    globals.set('#sumFail', poly(fun(TVariable(x), TVariable(y)), [x, y]));
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
        case TList(a) | TVector(a): stack.push(a);
        case TSum(_, items): for (item in items) stack.push(item);
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
        case TNumber | TExact | TBoolean | TText | TSyntax | TRecord(_):
        case TList(a) | TVector(a): stack.push(a);
        case TSum(_, items): for (item in items) stack.push(item);
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
        case [TNumber, TNumber] | [TExact, TExact] | [TBoolean, TBoolean] | [TText, TText] | [TSyntax, TSyntax]:
        case [TRecord(leftName), TRecord(rightName)] if (leftName == rightName):
        case [TList(x), TList(y)] | [TVector(x), TVector(y)]: stack.push({a:x, b:y});
        case [TSum(nx, xs), TSum(ny, ys)] if (nx == ny && xs.length == ys.length):
          for (i in 0...xs.length) stack.push({a:xs[i], b:ys[i]});
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
          case TVector(_): results.push(TVector(results.pop()));
          case TSum(name, types):
            var newArgs:Array<NType> = [];
            for (i in 0...types.length) newArgs.push(results.pop());
            newArgs.reverse();
            results.push(TSum(name, newArgs));
          case TFunction(_, _):
            var b = results.pop(), a = results.pop();
            results.push(TFunction(a, b));
          case _: throw 'Invalid type replacement frame';
        }
      } else switch (frame.type) {
        case TVariable(id):
          var current = mapping.get(id);
          results.push(current == null ? frame.type : current);
        case TSum(_, types):
          stack.push({type:frame.type, finish:true});
          var i = types.length;
          while (i > 0) { i--; stack.push({type:types[i], finish:false}); }
        case TList(a) | TVector(a):
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
        case TList(item) | TVector(item): stack.push(item);
        case TSum(_, types): for (item in types) stack.push(item);
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
          case TVector(_): results.push(TVector(results.pop()));
          case TSum(name, types):
            var newArgs:Array<NType> = [];
            for (i in 0...types.length) newArgs.push(results.pop());
            newArgs.reverse();
            results.push(TSum(name, newArgs));
          case TFunction(_, _):
            var b = results.pop(), a = results.pop();
            results.push(TFunction(a, b));
          case _: throw 'Invalid type normalization frame';
        }
      } else {
        var normalized = prune(frame.type);
        switch (normalized) {
          case TSum(_, types):
            stack.push({type:normalized, finish:true});
            var i = types.length;
            while (i > 0) { i--; stack.push({type:types[i], finish:false}); }
          case TList(a) | TVector(a):
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

  /** Dot syntax desugars to #recordGet receiver "field". The field
      projection type follows the receiver's *nominal* record type. When an
      unconstrained parameter is used, a unique field name can determine it;
      shared field names are reported as ambiguous rather than guessed. */
  function projectField(receiver:NType, field:String):NType {
    var recordName:Null<String> = null;
    switch (prune(receiver)) {
      case TRecord(name): recordName = name;
      case TVariable(_):
        var matches:Array<String> = [];
        for (name in records.keys()) if (globals.exists(name + '.' + field)) matches.push(name);
        if (matches.length == 0) throw 'Type error: unknown record field ' + field;
        if (matches.length > 1) {
          matches.sort(Reflect.compare);
          throw 'Type error: ambiguous record field ' + field + ' (' + matches.join(', ') + ')';
        }
        recordName = matches[0];
        unify(receiver, TRecord(recordName));
      case _: throw 'Type error: expected record before . ' + field;
    }
    var name:String = recordName;
    var accessor = globals.get(name + '.' + field);
    if (accessor == null) throw 'Type error: record ' + name + ' has no field ' + field;
    var fieldType = fresh();
    unify(instantiate(accessor), fun(TRecord(name), fieldType));
    return fieldType;
  }

  /** Hindley-Milner with explicit expression frames; let generalization stays at
      the direct-lambda application boundary, as in v0.12. */
  function infer(expr:Expr, env:StringMap<TypeScheme>, ?current:{name:String, scheme:TypeScheme}):NType {
    var work:Array<InferFrame> = [new InferFrame(expr, env)];
    var results:Array<NType> = [];
    while (work.length > 0) {
      var frame = work[work.length - 1];
      switch (frame.source) {
        case Literal(Number(_)): results.push(TNumber); work.pop();
        case Literal(ExactNumber(_)): results.push(TExact); work.pop();
        case Literal(Boolean(_)): results.push(TBoolean); work.pop();
        case Literal(Text(_)): results.push(TText); work.pop();
        case Literal(Nil): results.push(TList(fresh())); work.pop();
        case Literal(_): throw 'Type error: unsupported literal';
        case Var(name):
          var scheme:TypeScheme;
          if (StringTools.startsWith(name, MacroExpander.GLOBAL)) {
            var globalName = name.substr(MacroExpander.GLOBAL.length);
            scheme = current != null && current.name == globalName ? current.scheme : globals.get(globalName);
          } else scheme = frame.scope.get(name);
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
        case Apply(Apply(Var(get), receiver), Literal(Text(field))) if (MacroExpander.globalName(get) == '#recordGet'):
          if (frame.phase == 0) {
            frame.phase = 1;
            work.push(new InferFrame(receiver, frame.scope));
          } else {
            results.push(projectField(results.pop(), field));
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

  function fieldType(name:String):NType return switch (name) {
    case 'Number': TNumber;
    case 'Exact': TExact;
    case 'Bool': TBoolean;
    case 'Text' | 'String': TText;
    case 'Syntax': TSyntax;
    case _: if (!records.exists(name)) throw 'Type error: unknown record field type ' + name;
      TRecord(name);
  };

  /** Only atomic field types in this iteration. Parameters are lowercase names;
      nominal recursive sums without parameters are supported. */
  function sumFieldType(name:String, self:String, parameterTypes:StringMap<NType>):NType {
    var generic = parameterTypes.get(name);
    if (generic != null) return generic;
    return switch (name) {
      case 'Number': TNumber;
    case 'Exact': TExact;
      case 'Bool': TBoolean;
      case 'Text' | 'String': TText;
    case 'Syntax': TSyntax;
      case _: if (name == self && !sums.exists(self)) TSum(self, [])
        else if (records.exists(name)) TRecord(name)
        else if (sums.exists(name) && sums.get(name) == 0) TSum(name, [])
        else throw 'Type error: unknown or parameterized sum field type ' + name;
    };
  }

  /** v0.19: recognize the exact private lowering shape emitted by both
      parsers. This analysis doesn't extend the five-form expression AST.
      It validates constructor ownership, bindings and full coverage before
      ordinary Hindley-Milner inference runs. */
  function validateMatches(expr:Expr):Void {
    var pending:Array<Expr> = [expr];
    while (pending.length > 0) {
      var current = pending.pop();
      switch (current) {
        case Apply(Lambda(subject, body), _) if (subject == '#nail_sum_subject_0' ||
          (StringTools.startsWith(subject, '#macro_local_') && StringTools.endsWith(subject, '_#nail_sum_subject_0'))):
          var covered = new StringMap<Bool>();
          var owner:Null<String> = null;
          var branch:Expr = body;
          var count = 0;
          var finished = false;
          while (!finished) {
            switch (branch) {
              case If(condition, yes, no):
                var ctor:String = switch (condition) {
                  case Apply(Var(predicate), Var(receiver))
                    if (receiver == subject && StringTools.endsWith(predicate, '?')):
                    var name = MacroExpander.globalName(predicate);
                    name.substr(0, name.length - 1);
                  case _: throw 'Type error: malformed algebraic match branch';
                };
                var foundOwner = constructorOwners.get(ctor);
                if (foundOwner == null) throw 'Type error: unknown algebraic constructor ' + ctor;
                if (owner == null) owner = foundOwner;
                else if (owner != foundOwner) throw 'Type error: mixed constructors from ' + owner + ' and ' + foundOwner;
                if (covered.exists(ctor)) throw 'Type error: duplicate constructor branch ' + ctor;
                covered.set(ctor, true);
                var specs = sumCases.get(foundOwner);
                var expected = -1;
                for (spec in specs) if (spec.name == ctor) expected = spec.arity;
                if (expected < 0) throw 'Type error: unknown algebraic constructor ' + ctor;
                var observed = 0;
                var inner:Expr = yes;
                var bindings = true;
                while (bindings) {
                  switch (inner) {
                    case Apply(Lambda(_, rest), Apply(Var(getter), Var(receiver)))
                      if (receiver == subject && MacroExpander.globalName(getter) == ctor + '.' + observed):
                      observed++;
                      inner = rest;
                    case _: bindings = false;
                  }
                }
                if (observed != expected) throw 'Type error: constructor ' + ctor +
                  ' expects ' + expected + ' match bindings but got ' + observed;
                branch = no;
                count++;
              case Apply(Var(failName), Var(receiver)) if (receiver == subject && MacroExpander.globalName(failName) == '#sumFail'):
                if (owner == null || count == 0) throw 'Type error: empty algebraic match';
                var missing:Array<String> = [];
                for (spec in sumCases.get(owner)) if (!covered.exists(spec.name)) missing.push(spec.name);
                if (missing.length > 0) throw 'Type error: non-exhaustive match for ' + owner +
                  ': missing ' + missing.join(', ');
                finished = true;
              case _: throw 'Type error: malformed algebraic match fallback';
            }
          }
        case _:
      }
      switch (current) {
        case Apply(fn, arg): pending.push(arg); pending.push(fn);
        case Lambda(_, body): pending.push(body);
        case If(condition, yes, no): pending.push(no); pending.push(yes); pending.push(condition);
        case _:
      }
    }
  }

  /** A generated definition is checked against a declared monomorphic
      signature, including the types of free references and nominal fields.
      This is different from inferring/checking arbitrary unannotated code. */
  public function verifyGenerated(forms:Array<Form>,
      contracts:Array<{name:String, type:NType}>):Array<String> {
    if (forms.length != contracts.length)
      throw 'Generated type contract: definition count (expected '
        + contracts.length + ', got ' + forms.length + ')';
    var inferred:Array<String> = [];
    var used = new StringMap<Bool>();
    var validName = ~/^[A-Za-z_][A-Za-z_0-9]*$/;
    for (i in 0...contracts.length) {
      var contract = contracts[i];
      var name = contract.name;
      if (!validName.match(name) || StringTools.startsWith(name, '#'))
        throw 'Generated type contract: invalid definition name ' + name;
      if (used.exists(name) || globals.exists(name))
        throw 'Generated type contract: duplicate or existing definition ' + name;
      used.set(name, true);
      var pending:Array<NType> = [contract.type];
      while (pending.length > 0) {
        switch (pending.pop()) {
          case TVariable(_):
            throw 'Generated type contract: polymorphic signatures require a separate validation rule';
          case TRecord(owner):
            if (!records.exists(owner))
              throw 'Generated type contract: unknown record type ' + owner;
          case TSum(owner, arguments):
            if (!sums.exists(owner) || sums.get(owner) != arguments.length)
              throw 'Generated type contract: unknown sum type or arity ' + owner;
            for (arg in arguments) pending.push(arg);
          case TFunction(argument, result):
            pending.push(argument);
            pending.push(result);
          case TList(item) | TVector(item):
            pending.push(item);
          case _:
        }
      }
      var body:Expr = switch (forms[i]) {
        case Define(actual, definition) if (actual == name): definition;
        case Define(actual, _):
          throw 'Generated type contract: expected ' + name + ' at form ' + i
            + ', got ' + actual;
        case _:
          throw 'Generated type contract: expected definition ' + name + ' at form ' + i;
      };
      // Only this declared name is recursively in scope. Earlier generated
      // bindings are available; later ones are not (sequential semantics).
      var env = scopeCopy(globals);
      var expected = mono(contract.type);
      env.set(name, expected);
      validateMatches(body);
      var actualType = infer(body, env, {name:name, scheme:expected});
      unify(actualType, contract.type);
      globals.set(name, expected);
      inferred.push(describe(normalize(contract.type)));
    }
    return inferred;
  }

  public function run(forms:Array<Form>):Array<String> {
    var inferred:Array<NType> = [];
    for (form in forms) switch (form) {
      case SumType(name, params, constructors):
        if (globals.exists(name) || records.exists(name) || sums.exists(name)) throw 'Type error: already defined ' + name;
        var polyArgs:Array<NType> = [];
        var parameterTypes = new StringMap<NType>();
        var quantified:Array<Int> = [];
        for (param in params) {
          if (parameterTypes.exists(param)) throw 'Type error: duplicate type parameter';
          var id = nextId++;
          quantified.push(id);
          var variable = TVariable(id);
          polyArgs.push(variable);
          parameterTypes.set(param, variable);
        }
        var sumType:NType = TSum(name, polyArgs);
        var proposed:Array<{name:String, signature:TypeScheme}> = [];
        var used = new StringMap<Bool>();
        for (ctor in constructors) {
          if (used.exists(ctor.name) || globals.exists(ctor.name) || globals.exists(ctor.name + '?'))
            throw 'Type error: duplicate algebraic constructor ' + ctor.name;
          used.set(ctor.name, true);
          var args:Array<NType> = [];
          for (fieldName in ctor.fieldTypes) {
            if (fieldName == name && params.length > 0) throw 'Type error: parameterized recursive sum fields require explicit application';
            args.push(sumFieldType(fieldName, name, parameterTypes));
          }
          var ctorType:NType = sumType;
          var i = args.length;
          while (i > 0) { i--; ctorType = fun(args[i], ctorType); }
          proposed.push({name:ctor.name, signature:poly(ctorType, quantified)});
          proposed.push({name:ctor.name + '?', signature:poly(fun(sumType, TBoolean), quantified)});
          for (i in 0...args.length) proposed.push({name:ctor.name + '.' + i,
            signature:poly(fun(sumType, args[i]), quantified)});
        }
        if (constructors.length == 0) throw 'Type error: empty algebraic sum';
        for (entry in proposed) if (globals.exists(entry.name)) throw 'Type error: already defined ' + entry.name;
        sums.set(name, params.length);
        sumCases.set(name, [for (ctor in constructors) {name:ctor.name, arity:ctor.fieldTypes.length}]);
        for (ctor in constructors) constructorOwners.set(ctor.name, name);
        for (entry in proposed) globals.set(entry.name, entry.signature);
      case RecordType(name, fields):
        if (globals.exists(name) || records.exists(name) || sums.exists(name)) throw 'Type error: already defined ' + name;
        if (fields.length == 0 || fields.length > 128) throw 'Type error: invalid record field count';
        var result:NType = TRecord(name);
        var accessors:Array<{name:String, ty:NType}> = [];
        // Names must be checked before any mutation. Forward/self-reference is
        // postponed until algebraic types, so the field set is finite/acyclic.
        var used = new StringMap<Bool>();
        for (field in fields) {
          if (used.exists(field.name)) throw 'Type error: duplicate record field ' + field.name;
          used.set(field.name, true);
          var getter = name + '.' + field.name;
          if (globals.exists(getter)) throw 'Type error: already defined ' + getter;
          var ty = fieldType(field.typeName);
          accessors.push({name:getter, ty:fun(result, ty)});
        }
        var constructor:NType = result;
        var i = accessors.length;
        while (i > 0) {
          i--;
          // getter type is Record -> Field; re-use the parsed field position.
          constructor = fun(fieldType(fields[i].typeName), constructor);
        }
        globals.set(name, mono(constructor));
        for (entry in accessors) globals.set(entry.name, mono(entry.ty));
        records.set(name, true);
      case Define(name, expr):
        if (globals.exists(name)) throw 'Type error: already defined ' + name;
        // Recursive name is monomorphic during inference; generalized afterwards.
        var provisional = fresh();
        var env = scopeCopy(globals);
        env.set(name, mono(provisional));
        validateMatches(expr);
        var t = infer(expr, env, {name:name, scheme:mono(provisional)});
        unify(provisional, t);
        globals.set(name, generalize(t, globals));
      case Evaluate(expr):
        validateMatches(expr);
        inferred.push(infer(expr, globals));
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
        case TExact: output.add('Exact');
        case TBoolean: output.add('Bool');
        case TText: output.add('Text');
        case TRecord(name): output.add(name);
        case TSum(name, args):
          if (args.length == 0) output.add(name);
          else {
            stack.push({type:null, text:']', parens:false});
            for (i in 0...args.length) {
              var j = args.length - 1 - i;
              stack.push({type:args[j], text:null, parens:false});
              if (j > 0) stack.push({type:null, text:', ', parens:false});
            }
            stack.push({type:null, text:name + '[', parens:false});
          }
        case TSyntax: output.add('Syntax');
        case TVariable(id): output.add(label(id));
        case TVector(item):
          stack.push({type:null, text:']', parens:false});
          stack.push({type:item, text:null, parens:false});
          stack.push({type:null, text:'Vector[', parens:false});
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

