# NailSeed v0.31 — Runtime modules and separate compilation

This snapshot adds a **first working, explicitly typed runtime module linker**
to the v0.30 Nail compiler. Earlier snapshots remain unchanged.

## What works

- Independently compile ordinary Nail source files into portable, versioned
  `nailseed.runtime-module.v1` images, each containing **bytecode plus public
  imports/exports and their monomorphic type signatures**. Module linking
  requires no source parser, Nail source, or Haxe compiler.
- Each module executes in a **fresh, isolated ByteVm lexical environment**.
  Imports are bound by explicit aliases, and the consumer sees **only named
  exports**. Unexported declarations remain private; exported functions keep
  their own module's lexical environment when called from another module.
- Dependencies are resolved topologically. Missing modules/exports,
  duplicate aliases, duplicate modules, cycles and source-name shadowing
  are rejected. Module evaluation is initialization once, not global
  concatenation of all program definitions.
- Each source is checked by Hindley–Milner with imported names installed
  from explicitly declared **closed, monomorphic signatures**. Exported
  declarations are checked against their promised public signatures.
- The Haxe reference compiler and **Nail-written source-free bootstrap
  compiler must emit identical canonical bytecode** for each module.
- A legacy `Number` module and an opted-in `Exact` module get independent
  bytecode image envelopes (v1 vs v2-exact). Imports between distinct
  numeric dialects are explicitly rejected to prevent silent type changes.

## Module source files

The source files below are normal Nail files. They deliberately contain no
new runtime-module keywords. **The explicit import/export manifest is supplied
through the host API**; this is a staging step before choosing Nail-native
module syntax and typed source declarations.

<details>
<summary>Example module layout</summary>

```text
examples/
  module-core.nail      # private hidden, public double
  module-math.nail      # imports Core.double as core_double; exports triple
  module-app.nail       # imports Math.triple as math_triple; exports compute
  module-tempo.nail     # Exact rational seconds per beat
  module-phrase.nail    # imports Tempo.secondsPerBeat
```
</details>

To compile and link the first three files, a host provides manifests:

```haxe
var numberFn = TFunction(TNumber, TNumber);
var core:SourceModuleSpec = {
  name: 'Core',
  source: coreSource,
  imports: [],
  exports: [{name:'double', type:numberFn}]
};
var math:SourceModuleSpec = {
  name: 'Math',
  source: mathSource,
  imports: [{
    module:'Core', symbol:'double', alias:'core_double', type:numberFn
  }],
  exports: [{name:'triple', type:numberFn}]
};
var app:SourceModuleSpec = {
  name: 'Application',
  source: appSource,
  imports: [{
    module:'Math', symbol:'triple', alias:'math_triple', type:numberFn
  }],
  exports: [{name:'compute', type:numberFn}]
};

// Source is checked and compiled once. Images may be saved independently.
var artifacts = [core,math,app].map(spec ->
  ModuleImage.encode(ModuleLinker.compile(spec)));

// Source-free runtime: a different process can decode these images and link
// them in any order. The private Core.hidden symbol never becomes visible.
var bundle = ModuleLinker.linkImages([
  artifacts[2], artifacts[0], artifacts[1]
]);
var value = bundle.invoke('Application', 'compute', Number(14));
// Vm.toPlain(value) == 42
```

For the **music timing example**, the `Tempo` and `Phrase` modules opt into
`# nail: 0.29`, export/import `Exact -> Exact`, and evaluate
`phraseSeconds 128` as **`E:30720/97`**, exactly.

## Compiled interface and runtime guarantees

`ModuleImage` records module name, dialect, import aliases, exported names,
canonical signatures and a versioned bytecode envelope. `ModuleLinker.link`
can also work with in-memory compiled units, while
`ModuleLinker.linkImages` accepts only serialized images. No source-code
strings are supplied at link time.

Interfaces remain explicit **monomorphic** `NType` contracts. The first
version supports primitive and function/list/vector signatures. Public
nominal and polymorphic type interfaces need further design; local record or
sum type definitions are therefore deliberately excluded from this module
compilation entry point. This does not remove record/ADT support from the
ordinary Nail compiler.

The compiled unit is currently a **trusted build artifact**. ModuleImage
validates structural metadata and canonical bytecode serialization but
does **not** cryptographically verify publisher authenticity or prove that
arbitrary modified bytecode satisfies its advertised type signature.

## Run the tests

From `v0.31/`, after building the bootstrap image:

```sh
haxe seed-image.hxml
haxe runtime-modules-test-interp.hxml
haxe runtime-modules-test-js.hxml && node build/tests/runtime-modules.js
haxe runtime-modules-test-php.hxml && php build/tests/php-runtime-modules/index.php
```

The GitHub Actions workflow additionally runs the inherited v0.30 procedural
transformer, macro, exact-number, type checker, source-free bootstrap,
fixed-point, stress, CLI and distribution tests.

## Boundaries and next work

This is a **host-manifest module API**, not source-native
`import/export` syntax for runtime values. Existing `import ... from ...`
and `export ...` forms retain their established **compile-time macro**
meaning and are not reinterpreted. The next logical changes are a compact
source-language surface (or generated interface files), public polymorphic
and nominal signatures, then richer cross-module diagnostics and incremental
recompilation. The runtime still has no ambient file/network I/O capability.

See [SPEC.md](SPEC.md), the [v0.30 snapshot](../v0.30/) and
[the roadmap](../ROADMAP.md).
