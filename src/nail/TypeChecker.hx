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
  var records:StringMap<Int>;
  var sums:StringMap<Int>;
  var sumCases:StringMap<Array<{name:String, arity:Int}>>;
  var constructorOwners:StringMap<String>;
  var nextId:Int;
  var relationByName:haxe.ds.StringMap<String>;

  public function new() {
    var solver = new Inference(0, new StringMap<TypeScheme>(), new StringMap<Int>(), new StringMap<Int>(),
      new StringMap<Array<{name:String, arity:Int}>>(), new StringMap<String>());
    solver.installPrimitives();
    global = solver.globals;
    records = solver.records;
    sums = solver.sums;
    sumCases = solver.sumCases;
    constructorOwners = solver.constructorOwners;
    nextId = solver.nextId;
    relationByName = new haxe.ds.StringMap<String>();
  }

  /** Return the types of top-level expressions; definitions also get inferred. */
  public function check(source:String, ?modules:String->Null<String>):Array<String> {

    var parser = new Parser(source);
    var forms = parser.parse(modules);
    var solver = new Inference(nextId, global, records, sums, sumCases,
      constructorOwners, relationByName);
    solver.declarations = parser.declaredRelations;
    var inferred = solver.run(forms);
    // Commit only after the whole type-check succeeds.
    global = solver.globals;
    records = solver.records;
    sums = solver.sums;
    sumCases = solver.sumCases;
    constructorOwners = solver.constructorOwners;
    nextId = solver.nextId;
    relationByName = solver.relations;
    return inferred;
  }

  /** Infer/check an AST supplied as first-class Nail Syntax, without reparsing text. */
  public function checkSyntax(tree:Value):Array<String> {
    var solver = new Inference(nextId, global, records, sums, sumCases,
      constructorOwners, relationByName);
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

  /** Canonical, closed structural rows are sorted by name and non-empty.
      Validate explicit host manifests as well as inferred public types. */
  public static function validStructural(fields:Array<nail.NType.StructuralField>):Bool {
    if (fields == null || fields.length == 0 || fields.length > 128) return false;
    var previous:Null<String> = null;
    for (item in fields) {
      if (item == null || item.type == null || item.name == null ||
          !~/^[A-Za-z_][A-Za-z_0-9]*$/.match(item.name) ||
          item.name == '_' ||
          (previous != null && Reflect.compare(previous, item.name) >= 0))
        return false;
      previous = item.name;
    }
    return true;
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
      case TStructural(fields):
        if (!validStructural(fields))
          throw 'Module type error: invalid structural record interface';
        for (field in fields) pending.push(field.type);
      case TFunction(a, b): pending.push(b); pending.push(a);
      case TVariable(_):
        throw 'Module type error: polymorphic import signatures are not yet supported';
      case TSum('CoreResult', args) if (args.length == 2):
        for (arg in args) pending.push(arg);
      case TRecord(_) | TRecordApplied(_, _) | TSum(_, _):
        throw 'Module type error: cross-module nominal types require public interfaces';
    }
    global.set(name, {term:type, quantified:[], comparable:[]});
  }

  /** Read the fully inferred closed public type of an ordinary definition.
      Unlike a string signature, the returned NType can be used to build a
      checked module manifest. Only ground non-nominal types are accepted
      until the public type/interface identity ABI is defined. */
  public function closedPublicType(name:String):NType {
    var found = global.get(name);
    if (found == null) throw 'Public interface: unknown export ' + name;
    if (found.quantified.length > 0 || found.comparable.length > 0)
      throw 'Public interface: polymorphic export requires a quantified ABI: ' + name;
    var work:Array<NType> = [found.term];
    while (work.length > 0) switch (work.pop()) {
      case TNumber | TExact | TBoolean | TText | TSyntax:
      case TList(item) | TVector(item): work.push(item);
      case TStructural(fields):
        if (!validStructural(fields))
          throw 'Public interface: invalid structural record fields';
        for (field in fields) work.push(field.type);
      case TFunction(a, b): work.push(b); work.push(a);
      case TVariable(_):
        throw 'Public interface: unconstrained type variable in export ' + name;
      case TSum('CoreResult', args) if (args.length == 2):
        for (arg in args) work.push(arg);
      case TRecord(_) | TRecordApplied(_, _) | TSum(_, _):
        throw 'Public interface: nominal types require public type identity: ' + name;
    }
    return found.term;
  }


  /** A fully quantified, non-nominal Hindley-Milner scheme is an explicit
      public contract, not a type inferred from an untrusted module image.
      Free variables, phantom quantifiers and malformed Eq constraints are
      rejected rather than implicitly specialized. */
  public static function validatePublicScheme(scheme:TypeScheme,
      allowQualifiedRecords:Bool = false):TypeScheme {
    if (scheme == null || scheme.term == null || scheme.quantified == null ||
        scheme.comparable == null || scheme.quantified.length > 64 ||
        scheme.comparable.length > 64)
      throw 'Public interface: invalid quantified scheme';
    var quantified = new IntMap<Bool>();
    for (id in scheme.quantified) {
      if (id < 0 || quantified.exists(id))
        throw 'Public interface: duplicate or invalid type quantifier';
      quantified.set(id, true);
    }
    var comparable = new IntMap<Bool>();
    for (id in scheme.comparable) {
      if (!quantified.exists(id) || comparable.exists(id))
        throw 'Public interface: invalid Eq constraint';
      comparable.set(id, true);
    }
    var used = new IntMap<Bool>();
    var pending:Array<NType> = [scheme.term];
    var nodes = 0;
    while (pending.length > 0) {
      if (++nodes > 2048) throw 'Public interface: type scheme size limit exceeded';
      switch (pending.pop()) {
        case TNumber | TExact | TBoolean | TText | TSyntax:
        case TList(t) | TVector(t): pending.push(t);
        case TStructural(fields):
          if (!validStructural(fields))
            throw 'Public interface: invalid structural record fields';
          for (field in fields) pending.push(field.type);
        case TFunction(a, b): pending.push(b); pending.push(a);
        case TVariable(id):
          if (!quantified.exists(id))
            throw 'Public interface: free type variable in public scheme';
          used.set(id, true);
        case TRecord(name):
          if (!allowQualifiedRecords ||
              !~/^[A-Z][A-Za-z0-9]*_[A-Z][A-Za-z_0-9]*$/.match(name))
            throw 'Public interface: nominal types require public type identity';
        case TRecordApplied(name, args):
          if (!allowQualifiedRecords ||
              !~/^[A-Z][A-Za-z0-9]*_[A-Z][A-Za-z_0-9]*$/.match(name) ||
              args.length == 0 || args.length > 16)
            throw 'Public interface: nominal types require public type identity';
          for (arg in args) pending.push(arg);
        case TSum('CoreResult', args) if (args.length == 2):
          for (arg in args) pending.push(arg);
        case TSum(_, _):
          throw 'Public interface: algebraic public type identity is not implemented';
      }
    }
    for (id in scheme.quantified) if (!used.exists(id))
      throw 'Public interface: unused public quantifier';
    return {
      term:scheme.term,
      quantified:scheme.quantified.copy(),
      comparable:scheme.comparable.copy()
    };
  }

  static function rebasePublicType(term:NType, mapping:IntMap<NType>):NType {
    var work:Array<{type:NType, end:Bool}> = [{type:term, end:false}];
    var results:Array<NType> = [];
    while (work.length > 0) {
      var frame = work.pop();
      if (frame.end) {
        switch (frame.type) {
          case TList(_): results.push(TList(results.pop()));
          case TVector(_): results.push(TVector(results.pop()));
          case TFunction(_, _):
            var result = results.pop(), argument = results.pop();
            results.push(TFunction(argument, result));
          case TRecordApplied(name, args) | TSum(name, args):
            var parameters:Array<NType> = [];
            for (i in 0...args.length) parameters.push(results.pop());
            parameters.reverse();
            results.push(switch (frame.type) {
              case TSum(_, _): TSum(name, parameters);
              case _: TRecordApplied(name, parameters);
            });
          case TStructural(fields):
            var types:Array<NType> = [];
            for (i in 0...fields.length) types.push(results.pop());
            types.reverse();
            var rebuilt:Array<nail.NType.StructuralField> = [];
            for (i in 0...fields.length)
              rebuilt.push({name:fields[i].name, type:types[i]});
            results.push(TStructural(rebuilt));
          case _: throw 'Public interface: malformed type scheme';
        }
      } else switch (frame.type) {
        case TVariable(id): results.push(mapping.get(id));
        case TList(t) | TVector(t):
          work.push({type:frame.type, end:true});
          work.push({type:t, end:false});
        case TFunction(a, b):
          work.push({type:frame.type, end:true});
          work.push({type:b, end:false});
          work.push({type:a, end:false});
        case TRecordApplied(_, args) | TSum('CoreResult', args):
          work.push({type:frame.type, end:true});
          var i = args.length;
          while (i > 0) work.push({type:args[--i], end:false});
        case TStructural(fields):
          work.push({type:frame.type, end:true});
          var i = fields.length;
          while (i > 0) work.push({type:fields[--i].type, end:false});
        case TRecord(name): results.push(TRecord(name));
        case TSum(_, _):
          throw 'Public interface: algebraic public type identity is not implemented';
        case _: results.push(frame.type);
      }
    }
    return results.pop();
  }

  /** Return an exportable HM contract, including quantified variables and
      Eq constraints, without changing the inference environment. */
  public function publicScheme(name:String,
      allowQualifiedRecords:Bool = false):TypeScheme {
    if (relationByName.exists(name))
      throw 'Public interface: constrained numeric exports require a relation-aware ABI';
    var found = global.get(name);
    if (found == null) throw 'Public interface: unknown export ' + name;
    return validatePublicScheme(found, allowQualifiedRecords);
  }

  /** Import an independently supplied scheme with FRESH variable identities.
      Rebinding is essential: type IDs in two separate source modules may
      overlap, yet their universally quantified variables must remain
      independent. Every reference instantiates the imported scheme. */
  public function importPublicScheme(name:String, scheme:TypeScheme,
      allowQualifiedRecords:Bool = false):Void {
    if (!~/^[A-Za-z_][A-Za-z_0-9]*$/.match(name) || global.exists(name))
      throw 'Module type error: duplicate, invalid or reserved import alias ' + name;
    var safe = validatePublicScheme(scheme, allowQualifiedRecords);
    var mapping = new IntMap<NType>();
    var variables:Array<Int> = [];
    for (old in safe.quantified) {
      var fresh = nextId++;
      mapping.set(old, TVariable(fresh));
      variables.push(fresh);
    }
    var constraints:Array<Int> = [];
    for (old in safe.comparable) switch (mapping.get(old)) {
      case TVariable(id): constraints.push(id);
      case _: throw 'Public interface: malformed Eq constraint';
    }
    global.set(name, {
      term:rebasePublicType(safe.term, mapping),
      quantified:variables, comparable:constraints
    });
  }

  /** No mutation of this checker: useful for IDEs and preflight checks. */
  public function preview(source:String, ?modules:String->Null<String>):Array<String>
    return copy().check(source, modules);

  public function copy():TypeChecker {
    var instance = new TypeChecker();
    instance.global = new StringMap<TypeScheme>();
    for (name in global.keys()) instance.global.set(name, global.get(name));
    instance.records = new StringMap<Int>();
    for (name in records.keys()) instance.records.set(name, records.get(name));
    instance.sums = new StringMap<Int>();
    for (name in sums.keys()) instance.sums.set(name, sums.get(name));
    instance.sumCases = new StringMap<Array<{name:String, arity:Int}>>();
    for (name in sumCases.keys()) instance.sumCases.set(name, sumCases.get(name).copy());
    instance.constructorOwners = new StringMap<String>();
    for (name in constructorOwners.keys()) instance.constructorOwners.set(name, constructorOwners.get(name));
    instance.nextId = nextId;
    instance.relationByName = new haxe.ds.StringMap<String>();
    for (name in relationByName.keys())
      instance.relationByName.set(name, relationByName.get(name));
    return instance;
  }

  /** Print a polymorphic definition's inferred signature (e.g. a -> a). */
  public function signature(name:String):String {
    return new Inference(nextId, global, records, sums, sumCases, constructorOwners,
      relationByName).signature(name);
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
  public var namedFields:Array<{name:String, expr:Expr}>;
  public var namedTypes:Array<NType>;
  public var namedIndex:Int = 0;
  public function new(source:Expr, scope:StringMap<TypeScheme>) {
    this.source = source;
    this.scope = scope;
  }
}

/** Per-call unifier and program checker. It only mutates its private copy of globals. */
private class Inference {
  public var globals(default, null):StringMap<TypeScheme>;
  public var records(default, null):StringMap<Int>;
  public var sums(default, null):StringMap<Int>;
  public var sumCases(default, null):StringMap<Array<{name:String, arity:Int}>>;
  public var constructorOwners(default, null):StringMap<String>;
  public var nextId(default, null):Int;
  public final relations:haxe.ds.StringMap<String>;
  public var declarations:haxe.ds.StringMap<String>;
  final substitutions:IntMap<NType> = new IntMap<NType>();
  final eqRequired:IntMap<Bool> = new IntMap<Bool>();

  public function new(start:Int, initial:StringMap<TypeScheme>, knownRecords:StringMap<Int>,
      knownSums:StringMap<Int>, knownCases:StringMap<Array<{name:String, arity:Int}>>,
      knownOwners:StringMap<String>, ?knownRelations:haxe.ds.StringMap<String>) {
    nextId = start;
    relations = new haxe.ds.StringMap<String>();
    if (knownRelations != null)
      for (name in knownRelations.keys()) relations.set(name, knownRelations.get(name));
    declarations = new haxe.ds.StringMap<String>();
    globals = new StringMap<TypeScheme>();
    for (name in initial.keys()) globals.set(name, initial.get(name));
    records = new StringMap<Int>();
    for (name in knownRecords.keys()) records.set(name, knownRecords.get(name));
    sums = new StringMap<Int>();
    for (name in knownSums.keys()) sums.set(name, knownSums.get(name));
    sumCases = new StringMap<Array<{name:String, arity:Int}>>();
    for (name in knownCases.keys()) sumCases.set(name, knownCases.get(name).copy());
    constructorOwners = new StringMap<String>();
    for (name in knownOwners.keys()) constructorOwners.set(name, knownOwners.get(name));
  }

  function fresh():NType return TVariable(nextId++);

  /** A hygienic macro global reference cannot bypass a constrained call. */
  function constrainedName(name:String, scope:StringMap<TypeScheme>):Null<String> {
    var base = MacroExpander.globalName(name);
    if (!relations.exists(base)) return null;
    if (StringTools.startsWith(name, MacroExpander.GLOBAL) ||
        scope.get(base) == globals.get(base)) return base;
    return null;
  }

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
    for (name in ['exactFloor', 'exactCeil', 'exactTruncate', 'exactRoundEven'])
      globals.set(name, mono(fun(e, e)));
    globals.set('exactIsInteger', mono(fun(e, b)));
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
    // A well-known generic sum owner has a stable identity across module
    // images. All other user-defined sums remain module-private.
    var okId = nextId++, errorId = nextId++;
    var success = TVariable(okId), failure = TVariable(errorId);
    var result = TSum('CoreResult', [success, failure]);
    sums.set('CoreResult', 2);
    sumCases.set('CoreResult', [
      {name:'CoreOk', arity:1}, {name:'CoreErr', arity:1}
    ]);
    constructorOwners.set('CoreOk', 'CoreResult');
    constructorOwners.set('CoreErr', 'CoreResult');
    globals.set('CoreOk', poly(fun(success, result), [okId, errorId]));
    globals.set('CoreErr', poly(fun(failure, result), [okId, errorId]));
    globals.set('CoreOk?', poly(fun(result, b), [okId, errorId]));
    globals.set('CoreErr?', poly(fun(result, b), [okId, errorId]));
    globals.set('CoreOk.0', poly(fun(result, success), [okId, errorId]));
    globals.set('CoreErr.0', poly(fun(result, failure), [okId, errorId]));
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
        case TSum(_, items) | TRecordApplied(_, items): for (item in items) stack.push(item);
        case TStructural(fields): for (field in fields) stack.push(field.type);
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
        case TSum(_, items) | TRecordApplied(_, items): for (item in items) stack.push(item);
        case TStructural(fields): for (field in fields) stack.push(field.type);
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
        case [TRecordApplied(nx, xs), TRecordApplied(ny, ys)]
          if (nx == ny && xs.length == ys.length):
          for (i in 0...xs.length) stack.push({a:xs[i], b:ys[i]});
        case [TStructural(xs), TStructural(ys)]:
          if (xs.length != ys.length)
            throw 'Type error: cannot unify ' + describe(a) + ' with ' + describe(b);
          for (i in 0...xs.length) {
            if (xs[i].name != ys[i].name)
              throw 'Type error: cannot unify ' + describe(a) + ' with ' + describe(b);
            stack.push({a:xs[i].type, b:ys[i].type});
          }
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
          case TSum(name, types) | TRecordApplied(name, types):
            var newArgs:Array<NType> = [];
            for (i in 0...types.length) newArgs.push(results.pop());
            newArgs.reverse();
            results.push(switch (frame.type) {
              case TSum(_, _): TSum(name, newArgs);
              case _: TRecordApplied(name, newArgs);
            });
          case TStructural(fields):
            var types:Array<NType> = [];
            for (i in 0...fields.length) types.push(results.pop());
            types.reverse();
            var rebuilt:Array<nail.NType.StructuralField> = [];
            for (i in 0...fields.length)
              rebuilt.push({name:fields[i].name, type:types[i]});
            results.push(TStructural(rebuilt));
          case TFunction(_, _):
            var b = results.pop(), a = results.pop();
            results.push(TFunction(a, b));
          case _: throw 'Invalid type replacement frame';
        }
      } else switch (frame.type) {
        case TVariable(id):
          var current = mapping.get(id);
          results.push(current == null ? frame.type : current);
        case TSum(_, types) | TRecordApplied(_, types):
          stack.push({type:frame.type, finish:true});
          var i = types.length;
          while (i > 0) { i--; stack.push({type:types[i], finish:false}); }
        case TStructural(fields):
          stack.push({type:frame.type, finish:true});
          var i = fields.length;
          while (i > 0) stack.push({type:fields[--i].type, finish:false});
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
        case TSum(_, types) | TRecordApplied(_, types):
          for (item in types) stack.push(item);
        case TStructural(fields):
          for (field in fields) stack.push(field.type);
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
          case TSum(name, types) | TRecordApplied(name, types):
            var newArgs:Array<NType> = [];
            for (i in 0...types.length) newArgs.push(results.pop());
            newArgs.reverse();
            results.push(switch (frame.type) {
              case TSum(_, _): TSum(name, newArgs);
              case _: TRecordApplied(name, newArgs);
            });
          case TStructural(fields):
            var types:Array<NType> = [];
            for (i in 0...fields.length) types.push(results.pop());
            types.reverse();
            var rebuilt:Array<nail.NType.StructuralField> = [];
            for (i in 0...fields.length)
              rebuilt.push({name:fields[i].name, type:types[i]});
            results.push(TStructural(rebuilt));
          case TFunction(_, _):
            var b = results.pop(), a = results.pop();
            results.push(TFunction(a, b));
          case _: throw 'Invalid type normalization frame';
        }
      } else {
        var normalized = prune(frame.type);
        switch (normalized) {
          case TSum(_, types) | TRecordApplied(_, types):
            stack.push({type:normalized, finish:true});
            var i = types.length;
            while (i > 0) { i--; stack.push({type:types[i], finish:false}); }
          case TStructural(fields):
            stack.push({type:normalized, finish:true});
            var i = fields.length;
            while (i > 0) stack.push({type:fields[--i].type, finish:false});
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

  /** Extract the exact, private #cons list emitted by both named-record
      parsers. Each element retains its own expression and lexical scope.
      This does not attempt to infer a homogeneous Haxe list type. */
  static function namedItems(expr:Expr):Array<Expr> {
    var out:Array<Expr> = [];
    var current = expr;
    while (true) switch (current) {
      case Literal(Nil): return out;
      case Apply(Apply(Var('#cons'), head), tail):
        out.push(head);
        current = tail;
        if (out.length > 128)
          throw 'Type error: too many named record fields';
      case _:
        throw 'Type error: invalid named record constructor lowering';
    }
  }

  /** Dot syntax desugars to #recordGet receiver "field". The field
      projection type follows the receiver's *nominal* record type. When an
      unconstrained parameter is used, a unique field name can determine it;
      shared field names are reported as ambiguous rather than guessed. */
  function projectField(receiver:NType, field:String):NType {
    var recordName:Null<String> = null;
    switch (prune(receiver)) {
      case TRecord(name) | TRecordApplied(name, _): recordName = name;
      case TStructural(fields):
        for (item in fields) if (item.name == field) return item.type;
        throw 'Type error: structural record has no field ' + field;
      case TVariable(_):
        var matches:Array<String> = [];
        for (name in records.keys()) if (globals.exists(name + '.' + field)) matches.push(name);
        if (matches.length == 0) throw 'Type error: unknown record field ' + field;
        if (matches.length > 1) {
          matches.sort(Reflect.compare);
          throw 'Type error: ambiguous record field ' + field + ' (' + matches.join(', ') + ')';
        }
        recordName = matches[0];
      case _: throw 'Type error: expected record before . ' + field;
    }
    var name:String = recordName;
    var accessor = globals.get(name + '.' + field);
    if (accessor == null) throw 'Type error: record ' + name + ' has no field ' + field;
    var fieldType = fresh();
    unify(instantiate(accessor), fun(receiver, fieldType));
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
          if (constrainedName(name, frame.scope) != null)
            throw 'Type error: constrained function requires two directly applied arguments: ' + name;
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

        // Closed, explicit overload set; never infer overloaded operators
        // implicitly. Fully applied calls resolve on both argument types.
        case Apply(Apply(Var(name), firstArg), secondArg)
          if (constrainedName(name, frame.scope) != null):
          if (frame.phase == 0) {
            frame.phase = 1;
            work.push(new InferFrame(firstArg, frame.scope));
          } else if (frame.phase == 1) {
            frame.saved = results.pop();
            frame.phase = 2;
            work.push(new InferFrame(secondArg, frame.scope));
          } else {
            var other = results.pop();
            var ret = numeric.NumericRelation.result(
              relations.get(MacroExpander.globalName(name)),
              normalize(frame.saved), normalize(other));
            results.push(ret);
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
        case Apply(Apply(Apply(Var(make), Literal(Text(owner))), fieldNames), fieldValues)
          if (MacroExpander.globalName(make) == '#recordMake'):
          if (frame.phase == 0) {
            var structural = owner == '#struct';
            if (!structural && !records.exists(owner))
              throw 'Type error: unknown named record type ' + owner;
            var names = namedItems(fieldNames);
            var values = namedItems(fieldValues);
            if (names.length != values.length)
              throw 'Type error: malformed named record construction';
            var seen = new StringMap<Bool>();
            frame.namedFields = [];
            for (i in 0...names.length) {
              var field:String = switch (names[i]) {
                case Literal(Text(label)): label;
                case _: throw 'Type error: malformed named record field';
              };
              if (seen.exists(field)) throw 'Type error: duplicate named record field ' + field;
              seen.set(field, true);
              if (!structural && !globals.exists(owner + '.' + field))
                throw 'Type error: unknown named record field ' + owner + '.' + field;
              frame.namedFields.push({name:field, expr:values[i]});
            }
            if (structural) {
              frame.namedTypes = [];
            } else {
              var count = 0;
              for (key in globals.keys())
                if (StringTools.startsWith(key, owner + '.')) count++;
              if (count != frame.namedFields.length)
                throw 'Type error: missing named record field for ' + owner;
              var constructor = globals.get(owner);
              if (constructor == null) throw 'Type error: unknown named record type ' + owner;
              var resultType = instantiate(constructor);
              var scanning = true;
              while (scanning) switch (prune(resultType)) {
                case TFunction(_, next): resultType = next;
                case TRecord(label) if (label == owner): scanning = false;
                case TRecordApplied(label, _) if (label == owner): scanning = false;
                case _: throw 'Type error: invalid named record constructor ' + owner;
              }
              frame.saved = resultType;
            }
            frame.phase = 1;
            if (frame.namedFields.length > 0)
              work.push(new InferFrame(frame.namedFields[0].expr, frame.scope));
            else {
              results.push(frame.saved);
              work.pop();
            }
          } else {
            var valueType = results.pop();
            var currentField = frame.namedFields[frame.namedIndex];
            if (owner == '#struct') {
              frame.namedTypes.push(valueType);
            } else {
              var accessor = globals.get(owner + '.' + currentField.name);
              var fieldType = fresh();
              unify(instantiate(accessor), fun(frame.saved, fieldType));
              unify(valueType, fieldType);
            }
            frame.namedIndex++;
            if (frame.namedIndex < frame.namedFields.length)
              work.push(new InferFrame(frame.namedFields[frame.namedIndex].expr, frame.scope));
            else {
              if (owner == '#struct') {
                var fields:Array<nail.NType.StructuralField> = [];
                for (i in 0...frame.namedFields.length)
                  fields.push({name:frame.namedFields[i].name, type:frame.namedTypes[i]});
                fields.sort((a, b) -> Reflect.compare(a.name, b.name));
                if (!TypeChecker.validStructural(fields))
                  throw 'Type error: invalid structural record fields';
                results.push(TStructural(fields));
              } else results.push(frame.saved);
              work.pop();
            }
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

  function fieldType(name:String, ?params:StringMap<NType>):NType {
    var variable = params == null ? null : params.get(name);
    if (variable != null) return variable;
    return switch (name) {
      case 'Number': TNumber;
      case 'Exact': TExact;
      case 'Bool': TBoolean;
      case 'Text' | 'String': TText;
      case 'Syntax': TSyntax;
      case _:
        if (!records.exists(name)) throw 'Type error: unknown record field type ' + name;
        if (records.get(name) != 0)
          throw 'Type error: parameterized record field type requires explicit application: ' + name;
        TRecord(name);
    };
  }

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
        else if (records.exists(name) && records.get(name) == 0) TRecord(name)
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
            if (!records.exists(owner) || records.get(owner) != 0)
              throw 'Generated type contract: unknown record type ' + owner;
          case TRecordApplied(owner, arguments):
            if (!records.exists(owner) || records.get(owner) != arguments.length)
              throw 'Generated type contract: unknown record type or arity ' + owner;
            for (arg in arguments) pending.push(arg);
          case TSum(owner, arguments):
            if (!sums.exists(owner) || sums.get(owner) != arguments.length)
              throw 'Generated type contract: unknown sum type or arity ' + owner;
            for (arg in arguments) pending.push(arg);
          case TFunction(argument, result):
            pending.push(argument);
            pending.push(result);
          case TList(item) | TVector(item):
            pending.push(item);
          case TStructural(fields):
            if (!TypeChecker.validStructural(fields))
              throw 'Generated type contract: invalid structural record type';
            for (field in fields) pending.push(field.type);
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
      case RecordType(name, params, fields):
        if (globals.exists(name) || records.exists(name) || sums.exists(name)) throw 'Type error: already defined ' + name;
        if (fields.length == 0 || fields.length > 128) throw 'Type error: invalid record field count';
        if (params.length > 16) throw 'Type error: too many record type parameters';
        var parameterTypes = new StringMap<NType>();
        var quantified:Array<Int> = [];
        var parameters:Array<NType> = [];
        for (param in params) {
          if (!~/^[a-z][a-z0-9_]*$/.match(param) || parameterTypes.exists(param))
            throw 'Type error: invalid or duplicate record type parameter ' + param;
          var id = nextId++;
          quantified.push(id);
          var variable = TVariable(id);
          parameterTypes.set(param, variable);
          parameters.push(variable);
        }
        var result:NType = params.length == 0 ? TRecord(name) : TRecordApplied(name, parameters);
        var accessors:Array<{name:String, ty:NType}> = [];
        var constructorArgs:Array<NType> = [];
        // Fields remain atomic; nested applied types need a later syntax.
        var used = new StringMap<Bool>();
        for (field in fields) {
          if (used.exists(field.name)) throw 'Type error: duplicate record field ' + field.name;
          used.set(field.name, true);
          var getter = name + '.' + field.name;
          if (globals.exists(getter)) throw 'Type error: already defined ' + getter;
          var ty = fieldType(field.typeName, parameterTypes);
          constructorArgs.push(ty);
          accessors.push({name:getter, ty:fun(result, ty)});
        }
        var constructor:NType = result;
        var i = constructorArgs.length;
        while (i > 0) constructor = fun(constructorArgs[--i], constructor);
        globals.set(name, poly(constructor, quantified));
        for (entry in accessors) globals.set(entry.name, poly(entry.ty, quantified));
        records.set(name, params.length);
      case Define(name, expr):
        if (globals.exists(name)) throw 'Type error: already defined ' + name;
        var constrained = declarations.get(name);
        if (constrained != null) {
          // Each admitted signature is checked against the SAME body.
          // This is a finite overload contract, not inferred Num polymorphism.
          for (row in numeric.NumericRelation.rows(constrained)) {
            var validator = new Inference(nextId, globals, records, sums,
              sumCases, constructorOwners, relations);
            var expected = fun(row.left, fun(row.right, row.result));
            validator.globals.set('/', mono(expected));
            validator.globals.set(name, mono(expected));
            validator.validateMatches(expr);
            var inferredType = validator.infer(expr, validator.globals,
              {name:name, scheme:mono(expected)});
            validator.unify(inferredType, expected);
          }
          // The underlying closure is dynamically dispatched by the slash
          // primitive. Public ABI export is deferred until its serialized
          // type relation can be represented without losing constraints.
          globals.set(name, mono(fun(fresh(), fun(fresh(), fresh()))));
          relations.set(name, constrained);
          continue;
        }
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
    if (relations.exists(name))
      return numeric.NumericRelation.signature(relations.get(name));
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
        case TStructural(fields):
          stack.push({type:null, text:'}', parens:false});
          var i = fields.length;
          while (i > 0) {
            i--;
            stack.push({type:fields[i].type, text:null, parens:false});
            stack.push({type:null, text:fields[i].name + ': ', parens:false});
            if (i > 0) stack.push({type:null, text:', ', parens:false});
          }
          stack.push({type:null, text:'{', parens:false});
        case TSum(name, args) | TRecordApplied(name, args):
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

