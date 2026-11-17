package nail;

import haxe.ds.StringMap;
import nail.Ast.Form;
import nail.NType;
import nail.TypeScheme;
import nail.Value;
import nail.ModuleImage.CompiledModule;
import nail.ModuleImage.LinkedModuleImport;
import nail.ModuleImage.LinkedModuleExport;

/** An explicit, typed host manifest. These are runtime imports, NOT the
    v0.24+ compile-time import/export directives for expression macros. */
typedef SourceModuleImport = {
  var module:String;
  var symbol:String;
  var alias:String;
  var type:NType;
}

typedef SourceModuleExport = {
  var name:String;
  var type:NType;
}

typedef SourceModuleSpec = {
  var name:String;
  var source:String;
  var imports:Array<SourceModuleImport>;
  var exports:Array<SourceModuleExport>;
}

/** Optional export signature manifest: exported names are checked
    against the inferred closed source types rather than manually duplicated
    NType declarations. Polymorphic and nominal interfaces remain opt-in
    future work and are rejected instead of given an unsound signature. */
typedef InferredSourceModuleSpec = {
  var name:String;
  var source:String;
  var imports:Array<SourceModuleImport>;
  var exports:Array<String>;
}


/** Opt-in polymorphic import manifests keep the full typed HM scheme at
    compile time. The compiled image still uses the existing canonical
    string ABI; link time never needs source text or type inference. */
typedef PublicSourceModuleImport = {
  var module:String;
  var symbol:String;
  var alias:String;
  var scheme:TypeScheme;
}

typedef PublicSourceModuleSpec = {
  var name:String;
  var source:String;
  var imports:Array<PublicSourceModuleImport>;
  var exports:Array<String>;
}

/** Explicitly recoverable lookup outcomes at the host/module boundary.
    Once an exported function is called, any VM failure is NOT caught: a
    malformed image, resource-budget exhaustion or unexpected language bug
    must never be disguised as an ordinary application error. */
enum ModuleCallOutcome {
  CallSuccess(value:Value);
  MissingModule(name:String);
  MissingExport(module:String, symbol:String);
}

private typedef LinkedState = {
  var machine:ByteVm;
  var publicValues:StringMap<Value>;
  var signatures:StringMap<String>;
}

/** Runtime instances are private. A client may access only declared exports. */
class ModuleBundle {
  final instances:StringMap<LinkedState>;

  public function new(instances:StringMap<LinkedState>) {
    this.instances = instances;
  }

  function require(module:String):LinkedState {
    var state = instances.get(module);
    if (state == null) throw 'Module linker: unknown module ' + module;
    return state;
  }

  public function read(module:String, symbol:String):Value {
    var value = require(module).publicValues.get(symbol);
    if (value == null) throw 'Module linker: ' + module + ' does not export ' + symbol;
    return value;
  }

  public function signature(module:String, symbol:String):String {
    var value = require(module).signatures.get(symbol);
    if (value == null) throw 'Module linker: ' + module + ' does not export ' + symbol;
    return value;
  }

  /** A total lookup API for expected missing-module/export errors.
      Deliberately does not catch exceptions from the VM itself. */
  public function tryInvoke(module:String, symbol:String, value:Value):ModuleCallOutcome {
    var state = instances.get(module);
    if (state == null) return MissingModule(module);
    if (!state.publicValues.exists(symbol))
      return MissingExport(module, symbol);
    return CallSuccess(state.machine.invoke(symbol, value));
  }

  public function invoke(module:String, symbol:String, value:Value):Value {
    var state = require(module);
    if (!state.publicValues.exists(symbol))
      throw 'Module linker: ' + module + ' does not export ' + symbol;
    return state.machine.invoke(symbol, value);
  }
}

/** A separate compiler and a linker for immutable, explicitly typed Nail
    modules. No source parser, Haxe compiler or type inference is needed at
    link time: compiled images contain their own public interfaces.
    Runtime closure environments remain isolated per module. */
class ModuleLinker {
  public static inline var MAX_MODULES = 128;
  public static inline var MAX_DEPTH = 64;
  public static inline var DEFAULT_STEPS = 25000000;

  static function requireName(name:String, what:String):Void {
    if (!ModuleImage.validName(name))
      throw 'Module compiler: invalid ' + what + ' ' + name;
  }

  /** Printable canonical type signatures are produced by the existing
      Hindley-Milner checker, not by a second ad-hoc type formatter. */
  /** v0.48: never encode obsolete numeric types in a modern public ABI.
      This applies recursively to function, vector, list and record types. */
  static function requireModernType(type:NType):Void {
    var pending:Array<NType>=[type];
    while (pending.length > 0) switch (pending.pop()) {
      case TNumber | TExact:
        throw 'Module compiler: legacy Number/Exact type in modern numeric ABI';
      case TList(x) | TVector(x): pending.push(x);
      case TFunction(a,b): pending.push(a); pending.push(b);
      case TStructural(fields):
        for (f in fields) pending.push(f.type);
      case TRecordApplied(_,args) | TSum(_,args):
        for (x in args) pending.push(x);
      case _:
    }
  }

  static function numericDialect(source:String):String
    return numeric.LanguageVersion.isModern(source) ? 'modern'
      : numeric.NumericDialect.isExact(source) ? '0.29' : '0.27';

  static function moduleArtifact(name:String,source:String,
      imports:Array<LinkedModuleImport>,exports:Array<LinkedModuleExport>,
      code:Value):CompiledModule {
    var modern = numeric.LanguageVersion.isModern(source);
    return ModuleImage.decode(ModuleImage.encode({
      name:name, dialect:numericDialect(source),
      sourceVersion:modern ? numeric.LanguageVersion.declared(source) : null,
      imports:imports, exports:exports, code:code
    }));
  }

  static function signature(type:NType):String {
    var checker = new TypeChecker();
    checker.importSignature('_moduleInterface', type);
    return checker.signature('_moduleInterface');
  }


  /** Validate record type provenance at the *import provider* boundary.
      Re-exporting somebody else's nominal type is deliberately unsupported
      in this initial opaque-record slice. */
  static function requireRecordOwner(type:NType, module:String):Void {
    var pending:Array<NType> = [type];
    while (pending.length > 0) switch (pending.pop()) {
      case TRecord(name):
        if (!~/^[A-Z][A-Za-z0-9]*$/.match(module) ||
            !StringTools.startsWith(name, module + '_') ||
            !~/^[A-Z][A-Za-z_0-9]*$/.match(name.substr(module.length + 1)))
          throw 'Module compiler: imported nominal owner mismatch for '
            + name + ' from ' + module;
      case TRecordApplied(name, args):
        if (!~/^[A-Z][A-Za-z0-9]*$/.match(module) ||
            !StringTools.startsWith(name, module + '_') ||
            !~/^[A-Z][A-Za-z_0-9]*$/.match(name.substr(module.length + 1)))
          throw 'Module compiler: imported nominal owner mismatch for '
            + name + ' from ' + module;
        if (args.length == 0 || args.length > 16)
          throw 'Module compiler: invalid generic record arity';
        for (arg in args) pending.push(arg);
      case TStructural(fields):
        // Structural identity belongs to the field set, not the provider.
        // Any nominal field nested inside it still needs a verified owner.
        for (field in fields) pending.push(field.type);
      case TList(t) | TVector(t): pending.push(t);
      case TFunction(a, b): pending.push(b); pending.push(a);
      case TSum('CoreResult', args) if (args.length == 2):
        for (arg in args) pending.push(arg);
      case TSum(_, _):
        throw 'Module compiler: algebraic public type identity is not implemented';
      case _:
    }
  }

  /** Public schemes support polymorphic exports and imports with quantified
      variables and Eq constraints. The module-image format, VM and source
      language stay unchanged. This does not admit nominal public types. */
  public static function compilePublic(spec:PublicSourceModuleSpec,
      maxSteps:Int = DEFAULT_STEPS):CompiledModule {
    if (spec == null || spec.name == null || spec.source == null ||
        spec.imports == null || spec.exports == null)
      throw 'Module compiler: incomplete public interface manifest';
    requireName(spec.name, 'module name');
    if (spec.imports.length > 512 || spec.exports.length > 512)
      throw 'Module compiler: interface size limit exceeded';

    var modern = numeric.LanguageVersion.isModern(spec.source);
    var checker = new TypeChecker();
    var aliases = new StringMap<Bool>();
    var imports:Array<LinkedModuleImport> = [];
    for (item in spec.imports) {
      if (item == null) throw 'Module compiler: invalid public import';
      requireName(item.module, 'import module');
      requireName(item.symbol, 'import symbol');
      requireName(item.alias, 'import alias');
      if (aliases.exists(item.alias))
        throw 'Module compiler: duplicate import alias ' + item.alias;
      aliases.set(item.alias, true);
      TypeChecker.validatePublicScheme(item.scheme, true);
      if (modern) requireModernType(item.scheme.term);
      requireRecordOwner(item.scheme.term, item.module);
      checker.importPublicScheme(item.alias, item.scheme, true);
      imports.push({
        module:item.module, symbol:item.symbol, alias:item.alias,
        signature:checker.signature(item.alias)
      });
    }

    var defined = new StringMap<Bool>();
    function declare(name:String):Void {
      if (aliases.exists(name))
        throw 'Module compiler: declaration shadows imported alias ' + name;
      if (defined.exists(name))
        throw 'Module compiler: duplicate declaration ' + name;
      defined.set(name, true);
    }
    for (form in new Parser(spec.source).parse()) switch (form) {
      case Define(name, _): declare(name);
      case RecordType(name, _, fields):
        if (!~/^[A-Z][A-Za-z0-9]*$/.match(spec.name) ||
            !StringTools.startsWith(name, spec.name + '_') ||
            !~/^[A-Z][A-Za-z_0-9]*$/.match(name.substr(spec.name.length + 1)))
          throw 'Module compiler: nominal record owner mismatch: ' + name
            + ' must be qualified as ' + spec.name + '_Type';
        for (generated in RecordLowering.definitions(name, fields)) switch (generated) {
          case Define(symbol, _): declare(symbol);
          case _: throw 'Module compiler: malformed record lowering';
        }
      case SumType(_, _, _):
        throw 'Module compiler: algebraic public type identity is not implemented';
      case Evaluate(_):
        throw 'Module compiler: top-level expressions are not permitted';
    }

    checker.check(spec.source);
    var exports:Array<LinkedModuleExport> = [];
    var seen = new StringMap<Bool>();
    for (name in spec.exports) {
      requireName(name, 'export');
      if (seen.exists(name)) throw 'Module compiler: duplicate export ' + name;
      seen.set(name, true);
      if (!defined.exists(name))
        throw 'Module compiler: export must be a local definition ' + name;
      var publicScheme = checker.publicScheme(name, true); // sums still gated
      if (modern) requireModernType(publicScheme.term);
      exports.push({name:name, signature:checker.signature(name)});
    }

    var reference = BytecodeCompiler.compileSource(spec.source);
    var boot = new BootRuntime(maxSteps);
    var sourceFree = boot.compile(spec.source);
    if (BootstrapImage.encode(reference) != BootstrapImage.encode(sourceFree))
      throw 'Module compiler: reference and source-free Nail bytecode disagree';
    return moduleArtifact(spec.name,spec.source,imports,exports,sourceFree);
  }

  /** Derive monomorphic public signatures from source with the existing
      Hindley-Milner checker. The normal compile and link safety gates are
      retained, and no separate signature parser is introduced. */
  public static function compileInferred(spec:InferredSourceModuleSpec,
      maxSteps:Int = DEFAULT_STEPS):CompiledModule {
    if (spec == null || spec.name == null || spec.source == null ||
        spec.imports == null || spec.exports == null)
      throw 'Module compiler: incomplete inferred export manifest';
    requireName(spec.name, 'module name');
    if (spec.imports.length > 512 || spec.exports.length > 512)
      throw 'Module compiler: interface size limit exceeded';
    var modern = numeric.LanguageVersion.isModern(spec.source);
    var checker = new TypeChecker();
    for (item in spec.imports) {
      if (item == null) throw 'Module compiler: invalid imported signature';
      if (modern) requireModernType(item.type);
      checker.importSignature(item.alias, item.type);
    }
    checker.check(spec.source);
    var seen = new StringMap<Bool>();
    var generated:Array<SourceModuleExport> = [];
    for (name in spec.exports) {
      requireName(name, 'export');
      if (seen.exists(name)) throw 'Module compiler: duplicate export ' + name;
      seen.set(name, true);
      var declaredType = checker.closedPublicType(name);
      if (modern) requireModernType(declaredType);
      generated.push({name:name, type:declaredType});
    }
    // compile() still requires the export to be a genuine local definition,
    // rechecks it against the derived contract, and compares both compilers.
    return compile({
      name:spec.name, source:spec.source, imports:spec.imports,
      exports:generated
    }, maxSteps);
  }

  /** Compile source in isolation against its declared imports. Then compare
      the independent Haxe and self-hosted Nail compiler outputs. */
  public static function compile(spec:SourceModuleSpec,
      maxSteps:Int = DEFAULT_STEPS):CompiledModule {
    if (spec == null || spec.source == null || spec.imports == null || spec.exports == null)
      throw 'Module compiler: incomplete module manifest';
    requireName(spec.name, 'module name');
    if (spec.imports.length > 512 || spec.exports.length > 512)
      throw 'Module compiler: interface size limit exceeded';
    var modern = numeric.LanguageVersion.isModern(spec.source);
    var checker = new TypeChecker();
    var importedNames = new StringMap<Bool>();
    var importedContracts:Array<LinkedModuleImport> = [];
    for (item in spec.imports) {
      requireName(item.module, 'import module');
      requireName(item.symbol, 'import symbol');
      requireName(item.alias, 'import alias');
      if (importedNames.exists(item.alias))
        throw 'Module compiler: duplicate import alias ' + item.alias;
      importedNames.set(item.alias, true);
      if (modern) requireModernType(item.type);
      checker.importSignature(item.alias, item.type);
      importedContracts.push({
        module:item.module, symbol:item.symbol, alias:item.alias,
        signature:signature(item.type)
      });
    }

    // Source and imported bindings cannot share the same name. Importing is
    // explicit: no global access into other modules' private declarations.
    var forms = new Parser(spec.source).parse();
    var defined = new StringMap<Bool>();
    for (form in forms) switch (form) {
      case Define(name, _):
        if (importedNames.exists(name))
          throw 'Module compiler: declaration shadows imported alias ' + name;
        if (defined.exists(name))
          throw 'Module compiler: duplicate declaration ' + name;
        defined.set(name, true);
      case RecordType(_, _, _) | SumType(_, _, _):
        throw 'Module compiler: exported nominal type interfaces are not yet supported';
      case Evaluate(_):
        throw 'Module compiler: top-level expressions are not permitted';
    }

    checker.check(spec.source);
    var exports:Array<LinkedModuleExport> = [];
    var seen = new StringMap<Bool>();
    for (item in spec.exports) {
      requireName(item.name, 'export');
      if (seen.exists(item.name)) throw 'Module compiler: duplicate export ' + item.name;
      seen.set(item.name, true);
      if (!defined.exists(item.name))
        throw 'Module compiler: export must be a local definition ' + item.name;
      if (modern) requireModernType(item.type);
      var declared = signature(item.type);
      var inferred = checker.signature(item.name);
      if (inferred != declared)
        throw 'Module compiler: export type mismatch for ' + item.name
          + ' (declared ' + declared + ', inferred ' + inferred + ')';
      exports.push({name:item.name, signature:declared});
    }

    var reference = BytecodeCompiler.compileSource(spec.source);
    var boot = new BootRuntime(maxSteps);
    var sourceFree = boot.compile(spec.source);
    if (BootstrapImage.encode(reference) != BootstrapImage.encode(sourceFree))
      throw 'Module compiler: reference and source-free Nail bytecode disagree';
    // Round-trip independently compiled source-free bytecode and v2 ABI.
    // The linker sees only portable interfaces, never source text.
    return moduleArtifact(spec.name,spec.source,importedContracts,exports,sourceFree);
  }

  static function elements(list:Value):Array<Value> {
    var out:Array<Value> = [];
    var cursor = list;
    while (true) switch (cursor) {
      case Nil: return out;
      case Cons(a, b): out.push(a); cursor = b;
      case _: throw 'Module linker: malformed bytecode list';
    }
  }

  /** Record lowering generates private dotted getters. They are local
      bytecode names, never public manifest symbols or imported aliases. */
  static function validLocalBytecodeName(name:String):Bool {
    return ModuleImage.validName(name) ||
      ~/^[A-Z][A-Za-z_0-9]*\.[A-Za-z_][A-Za-z_0-9]*$/.match(name);
  }

  /** A compiled module can initialize only its own declarations: no EVAL
      forms that could perform work before dependency imports are installed. */
  static function inspect(module:CompiledModule):Void {
    var names = new StringMap<Bool>();
    var aliases = new StringMap<Bool>();
    for (item in module.imports) aliases.set(item.alias, true);
    var forms = switch (module.code) {
      case SyntaxNode('Bytecode', children): elements(children);
      case _: throw 'Module linker: expected Bytecode';
    };
    for (form in forms) switch (form) {
      case SyntaxNode('DEFINE', Cons(SyntaxLeaf('Name', name), Cons(_, Nil))):
        if (!validLocalBytecodeName(name))
          throw 'Module linker: invalid local definition ' + name;
        if (names.exists(name) || aliases.exists(name))
          throw 'Module linker: duplicate or shadowed definition ' + name;
        names.set(name, true);
      case _:
        throw 'Module linker: only local definitions are allowed in a module image';
    }
    for (item in module.exports) if (!names.exists(item.name))
      throw 'Module linker: missing exported definition ' + item.name;
  }

  /** Link already compiled images, resolving dependencies topologically.
      Each module is initialized exactly once in a fresh VM with an isolated
      environment and imports supplied only from a dependency's public API. */
  public static function link(modules:Array<CompiledModule>,
      maxSteps:Int = DEFAULT_STEPS, ?hostGrants:HostTextGrants):ModuleBundle {
    if (modules == null || modules.length == 0 || modules.length > MAX_MODULES)
      throw 'Module linker: invalid module count';
    var byName = new StringMap<CompiledModule>();
    for (module in modules) {
      // Also validate the caller's in-memory metadata (decode rejects
      // malformed external module images before invoking link).
      module = ModuleImage.decode(ModuleImage.encode(module));
      if (byName.exists(module.name))
        throw 'Module linker: duplicate module ' + module.name;
      inspect(module);
      byName.set(module.name, module);
    }

    var states = new StringMap<LinkedState>();
    var visiting = new StringMap<Bool>();
    var stack:Array<String> = [];
    function initialize(name:String):Void {
      if (states.exists(name)) return;
      if (visiting.exists(name))
        throw 'Module linker: cyclic imports ' + stack.concat([name]).join(' -> ');
      if (stack.length >= MAX_DEPTH)
        throw 'Module linker: dependency nesting limit exceeded';
      var module = byName.get(name);
      if (module == null) throw 'Module linker: missing dependency ' + name;
      visiting.set(name, true);
      stack.push(name);
      var runtime = new ByteVm(maxSteps);
      for (item in module.imports) {
        if (item.module == HostTextGrants.PROVIDER) {
          if (hostGrants == null)
            throw 'Module linker: missing host grants for ' + name;
          // A reserved host provider is not a Nail module. Only this
          // path can resolve and inject a host-constructed function value.
          runtime.linkImport(item.alias,
            hostGrants.resolve(name, item.symbol, item.signature));
          continue;
        }
        initialize(item.module);
        var dependency = byName.get(item.module);
        if (dependency.dialect != module.dialect)
          throw 'Module linker: incompatible numeric dialect '
            + item.module + ' -> ' + name;
        var dependencyState = states.get(item.module);
        var supplied = dependencyState.publicValues.get(item.symbol);
        var declared = dependencyState.signatures.get(item.symbol);
        if (supplied == null || declared == null)
          throw 'Module linker: ' + item.module + ' does not export ' + item.symbol;
        if (declared != item.signature)
          throw 'Module linker: import type mismatch for ' + name + '.'
            + item.alias + ' (expected ' + item.signature
            + ', got ' + declared + ')';
        runtime.linkImport(item.alias, supplied);
      }
      var evaluated = runtime.run(module.code);
      if (evaluated.length != 0)
        throw 'Module linker: modules cannot emit top-level evaluations';
      var publicValues = new StringMap<Value>();
      var signatures = new StringMap<String>();
      for (item in module.exports) {
        publicValues.set(item.name, runtime.readExport(item.name));
        signatures.set(item.name, item.signature);
      }
      stack.pop();
      visiting.remove(name);
      states.set(name, {
        machine:runtime, publicValues:publicValues, signatures:signatures
      });
    }

    var names:Array<String> = [for (name in byName.keys()) name];
    names.sort(Reflect.compare);
    for (name in names) initialize(name);
    return new ModuleBundle(states);
  }

  /** Signed deployment manifest: verify release and Ed25519 signature
      using native Node/PHP crypto, then verify EVERY module image before
      linking any host capability. In unsupported targets this fails closed. */
  public static function linkSignedImages(images:Array<String>,
      manifest:String, policy:ModuleSigningPolicy,
      maxSteps:Int = DEFAULT_STEPS, ?hostGrants:HostTextGrants):ModuleBundle {
    return linkSignedImagesWithVerifier(images, manifest, policy,
      NativeEd25519.verify, maxSteps, hostGrants);
  }

  /** Adapter boundary for embedders supplying another trusted synchronous
      Ed25519 verifier (e.g. an interpreter that calls an OS crypto API).
      Supplying a permissive callback entirely voids manifest authentication. */
  public static function linkSignedImagesWithVerifier(images:Array<String>,
      manifest:String, policy:ModuleSigningPolicy,
      verifier:String->String->String->Bool,
      maxSteps:Int = DEFAULT_STEPS, ?hostGrants:HostTextGrants):ModuleBundle {
    var approved = SignedModuleManifest.verify(manifest, policy, verifier);
    return link(approved.verify(images), maxSteps, hostGrants);
  }

  /** Opt-in integrity gate: the host supplies independently trusted image
      digests and name bindings, and ALL inputs are verified before linking.
      A digest is not an authenticated publisher signature. For permissioned
      modules use this API instead of the legacy linkImages method. */
  public static function linkTrustedImages(images:Array<String>,
      policy:ModuleImageTrust, maxSteps:Int = DEFAULT_STEPS,
      ?hostGrants:HostTextGrants):ModuleBundle {
    if (policy == null)
      throw 'Module trust: missing host pin policy';
    return link(policy.verify(images), maxSteps, hostGrants);
  }

  /** Link from JSON artifacts only: source files are not reparsed, inferred
      or compiled at runtime. */
  public static function linkImages(images:Array<String>,
      maxSteps:Int = DEFAULT_STEPS, ?hostGrants:HostTextGrants):ModuleBundle {
    return link([for (data in images) ModuleImage.decode(data)], maxSteps, hostGrants);
  }
}
