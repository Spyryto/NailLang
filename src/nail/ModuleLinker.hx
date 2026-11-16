package nail;

import haxe.ds.StringMap;
import nail.Ast.Form;
import nail.NType;
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
  static function signature(type:NType):String {
    var checker = new TypeChecker();
    checker.importSignature('_moduleInterface', type);
    return checker.signature('_moduleInterface');
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
      case RecordType(_, _) | SumType(_, _, _):
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
    var module:CompiledModule = {
      name:spec.name,
      dialect:numeric.NumericDialect.isExact(spec.source) ? '0.29' : '0.27',
      imports:importedContracts,
      exports:exports,
      code:sourceFree
    };
    // Round-trip the actual independently compiled artifact. The linker sees
    // only the decoded portable interface and the bytecode, never source text.
    return ModuleImage.decode(ModuleImage.encode(module));
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
        if (!ModuleImage.validName(name))
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
      maxSteps:Int = DEFAULT_STEPS):ModuleBundle {
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

  /** Link from JSON artifacts only: source files are not reparsed, inferred
      or compiled at runtime. */
  public static function linkImages(images:Array<String>,
      maxSteps:Int = DEFAULT_STEPS):ModuleBundle {
    return link([for (data in images) ModuleImage.decode(data)], maxSteps);
  }
}
