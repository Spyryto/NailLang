# NailSeed v0.25 — Record declaration transformation experiment

The Nail compiler now expands record declarations into an inspectable `Program`
of ordinary `Define` forms **before** emitting bytecode. Constructor and getter
semantics are unchanged; the independent Haxe `RecordLowering` remains the oracle.

This extracts existing Nail generation logic from the bytecode emitter. It is a
trusted standard transformer written as ordinary Nail functions, not yet a public
procedural-macro registration API.

```nail
# With the standard library loaded:
def source = parseSource " type Person { name Text age Number } ; " ;
def plan = expandRecordDeclarations source ;
recordExpansionSource plan ;
recordExpansionRuntime plan ;
```

`RecordExpansion` contains two syntax Programs:

- `source`: original declarations and expressions, after expression macro expansion
  when used by the compiler. Nominal type checking uses this Program.
- `runtime`: record declarations replaced by constructor/getter definitions, in order.
  Other forms, including ADT declarations, are retained.

Host clients may call `vm.expandRecordsWithNail(source, optionalModuleResolver)`
after `vm.loadStdlib()`. The compiler calls the same transformer automatically.
The functions are also available in the source-free bootstrap distribution.
Parser error values propagate unchanged.

## Validation

`RecordExpansionTestMain` checks source retention, exact AST equivalence with the
independent Haxe lowering, bytecode identity, execution, nominal type diagnostics,
imported expression macros, nested/shared fields, the 128-field limit, deterministic
output, and the precompiled runtime. Run it on Haxe, JS and PHP:

```sh
haxe seed-image.hxml
haxe record-expansion-test-interp.hxml
haxe record-expansion-test-js.hxml
node build/tests/record-expansion.js
haxe record-expansion-test-php.hxml
php build/tests/php-record-expansion/index.php
haxe rebootstrap-image.hxml
```

The v0.25 workflow also runs the inherited regression suites and verifies the
Haxe -> Nail -> Nail bootstrap fixed point.

## What this establishes

Generation can be separated from bytecode emission without changing the executable
core or runtime. Its output can be inspected, independently compiled and compared.
Preserving the original declaration avoids trying to infer a nominal record type
from erased primitive calls.

This is an architectural improvement, not a measured speedup or source-size saving.
The extra pass allocates an intermediate Program. No runtime instructions are added.

## Deliberate boundaries

- The input must be parser-validated syntax. This is a compiler-internal API, not a
  validator for arbitrary hand-crafted Syntax trees.
- Checking `source` validates user code against the trusted transformer contract;
  it does not prove that arbitrary generated code respects that contract.
- Keeping original syntax is declaration-level provenance, **not source spans**.
- General hygienic binding objects, quotation over surface syntax, pluggable
  declaration transformers and generated-code type validation remain future work.
- `let` and `match` still lower in the parser. ADTs still lower in the emitter.
- The reference Haxe execution/compiler path intentionally remains independent.
- `compileForms` now takes record-expanded forms; use `compileSyntax` for a complete
  compilation. The internal bytecode helpers `compileRecordType` and
  `recordAccessor` are replaced by syntax-producing `recordDefinitions` and
  `recordAccessorDefinition`.

See [DSL-DESIGN.md](DSL-DESIGN.md) for the next design choices.
