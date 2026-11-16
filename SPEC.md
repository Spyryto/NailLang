# v0.30 delta — Typed procedural declaration transformers

This stage exposes Nail-authored `Syntax -> Syntax` functions through
`ProceduralTransformer`, a **host-side orchestration API**, while preserving
all v0.29-runtime semantics and the same five expression constructors.

## Public contract

1. A valid source `SyntaxNode('Program', ...)` and a Nail transformer module
   are supplied explicitly. TypeChecker must infer the selected entry as
   exactly `Syntax -> Syntax`; unbound symbols or other signatures fail.
2. The module executes in an ordinary `Vm` or in the source-free
   `BootRuntime`. The user's Nail source creates first-class Syntax and
   returns a `Program` consisting exclusively of new `Define` forms.
3. `ProceduralHygiene.prepare` rewrites explicit local markers and rejects
   unexpected binders; `verifyPrepared` confirms all IDs are private,
   unique and lexically bound.
4. `GeneratedDeclarationValidator.validateTyped` checks every fresh
   definition against a caller-provided manifest of `{name, type:NType}`.
   Names must be fresh and signatures **closed and monomorphic**. The source
   program supplies existing types, functions and nominal fields. The type
   environment is transactional.
5. `ProceduralTransformer.compile` re-verifies prepared syntax and type
   contracts, appends generated declarations in order, and compiles them
   through the unchanged structured bytecode compiler.
6. `BootRuntime.compileSyntax` and the AST VM's compileSyntax path must
   generate the **same canonical bytecode**, and the host/bootstrap
   transformers must generate the same hygienic Syntax.

## Hygiene specification

- Generated binders have an explicit lexical role, distinguished from
  arbitrary caller `Var` references. The transformer author emits
  `#proc_local_x` as a Lambda Name and in the corresponding bound Vars.
- Each introduced binder receives a deterministic unique private ID
  `#proc_gensym_<serial>_<name>` on output. Nested markers obey lexical
  shadowing. Existing ordinary source names remain untouched, so unmarked
  free caller references cannot be captured by a generated binder.
- A new Lambda with an unmarked binder is rejected rather than guessing
  which variables to rename. Unbound markers and references to private
  IDs constructed directly by the generator fail.
- The final compilation boundary rejects raw markers, unbound private
  identifiers and reused private binding IDs.
- The transform has a bounded expansion traversal depth and node budget.
  Interpreter instruction budgets apply while running the generator.

This is strict, deliberately **opt-in hygiene**, not a claim of automatic
origin-aware hygiene for arbitrary syntax splices or intentional capture
annotations. The underlying v0.26 token/AST provenance metadata is not
serialized into the five-constructor AST or runtime bytecode.

## Security and failure boundaries

- Generated declarations are checked before compilation; only new
  definitions can be returned, no top-level `Evaluate` forms or new type
  declarations. Returned source trees do not silently change the original.
- No host file access, network access or reflection is exposed to user Nail
  transformers. They execute through normal lexical bindings and primitives.
- Generator type errors, invalid output shapes, duplicate declarations,
  invalid names, unbound variables and incompatible claimed return types
  are compile-time errors.
- `NType` manifest construction and scheduling are performed in the host,
  not via a new `macro` source-language declaration syntax.
- Source-free bootstrap execution, PHP/JS runtime parity and unchanged
  legacy/exact numeric behavior are required CI checks.

## Later work

General polymorphic generated signatures need rigid/skolem verification.
Unrestricted program rewriting needs per-origin binder identities and a
more expressive Syntax/phase contract. A source-language registration
surface may wrap this host API later, after the error and hygiene contract
has demonstrated value without adding new VM instructions.

---

# v0.29-runtime delta: real exact-number execution, isolated from v0.27

This directory is a full standalone snapshot of the v0.27 compiler and both
interpreters, modified to support an explicit numeric source dialect. It
reuses the independently tested v0.29 compact-number engine. The previous
v0.27 and v0.29 directory trees are not modified.

## Source language semantics

- No header or `# nail: 0.27`: legacy `Value.Number(Float)`, `TNumber`,
  legacy builtin operators, v1 bytecode images and unchanged outputs.
- First nonempty line `# nail: 0.29`: all numeric literals use
  `Value.ExactNumber(FastValue)` and `TExact`, with `Small(Int)` for
  values in signed ±2²⁶ range and `Fraction(Rational)` otherwise.
- The five-expression core remains unchanged. Infix `+ - * / < <= > >=`
  compile into statically typed separate exact builtins (`#exact...`).
  Equality remains polymorphic and rejects a mixed exact/Float comparison
  at runtime. There is no general numeric operator type class.
- Exact functions, recursion, nominal record fields declared as `Number`,
  sum payloads, vectors, text lengths/indices and macro-expanded literal
  expressions use exact arithmetic in the opted-in file.
- In this version, `Number` used as an annotation in exact-dialect nominal
  fields maps to internal `Exact`. In the existing dialect it means Float.
  A future public type-spelling design may choose a different explicit name.
- Explicit conversion `exactToFloat : Exact -> Number` uses a conservative
  finite-magnitude bridge and may round; `exactFromText : Text -> Exact`
  constructs an exact rational from ASCII numeric text. There is **no**
  silent cross-domain promotion.
- Attempts to import macro modules with incompatible numeric dialects
  are rejected. A general typed runtime module linker is not yet available.

## Compiler/VM boundary

- Haxe parser directly constructs exact literals from **original source
  spelling**, without first converting via IEEE-754.
- The Nail-written parser produces ordinary Syntax, and the new
  `exactRewrite` transformation runs **after macro expansion**, rewriting
  numeric literals, numeric operator names and nominal field-type tags.
  `exactEncode` is a bounded host primitive that canonicalizes decimal
  literal text before bytecode generation. `compileExactSource` is a
  Nail-written compilation entry point.
- `SyntaxLeaf('ExactNumber', 'E:n/d')` is a literal encoded as ASCII
  numerator/denominator strings (canonical, reduced, denominator positive).
  This is a new leaf tag inside the existing stack bytecode instruction set,
  not an additional opcode or expression constructor.
- Both `Vm` and `ByteVm` evaluate the same exact values. The source-free
  `BootRuntime` routes opted-in source to the bootstrapped
  `compileExactSource` function; the Haxe parser is not invoked.
- v1 `BootstrapImage` still embeds the legacy compiler image, while
  `ExactImage` offers an explicit v2-exact transport envelope with a
  required `sourceDialect=0.29`. A v1 decoder rejects that v2 envelope.
  Exact payloads are never converted to JSON numbers.
- The reference Haxe compiler and Nail-written compiler are required to
  produce *identical* canonical structured bytecode for both dialects,
  including the source-free bootstrap and Haxe/JS/PHP backends.

## Deliberate limits

- `Exact` is a numeric *domain*, not a dependent integer subtype. A
  fractional array index type-checks as `Exact` but is rejected by the VM.
- The simple rational engine uses decimal-digit BigNat and bounded digit
  budgets; it remains significantly slower than Float for fractional-heavy
  arithmetic. Production heap/time budgets and optimized large-integer
  algorithms remain future work.
- Explicit conversions from Float to Exact are deliberately absent because
  interpreting a binary approximation as a decimal string or an exact
  binary fraction requires a documented policy.
- Runtime module imports/exports and full mixed-version module linking are
  not implemented. Only the existing macro module boundary is checked.
- Bytecode-image format changes are opt-in: legacy bytecode and bootstrap
  image compatibility are mandatory regression gates.

---

# v0.27 delta: checked record-generation contract (opt-in)

`GeneratedDeclarationValidator.validate` accepts only a well-formed
`RecordExpansion [sourceProgram, runtimeProgram]`. It first type-checks
`sourceProgram`, then independently reconstructs the expected constructor
and getter definitions through the Haxe reference `RecordLowering`.
Every generated form and every preserved source form must be structurally
identical to the expected result; extra/missing/modified declarations fail.
On success, it returns `runtimeProgram` unchanged.

`Vm.validatedRecordsWithNail` and `Vm.compileValidatedWithNail` expose
this trusted, explicit validation path. Regular compilation and source-free
bootstrap remain unchanged. This exact-lowering record contract is separate from the host-side generic
monomorphic generated-definition checker below; neither exposes a public
procedural-macro registration API.

## Generic typed generated definitions (host-side)

`TypeChecker.checkGenerated(sourceSyntax, generatedSyntax, contracts)` is a
transactional type-checking entry point for a generated Program consisting
**only of fresh definitions** in the same order as a manifest of
`{name:String, type:NType}` contracts. Source syntax is checked first and
provides nominal types and earlier source bindings. Each generated
definition is inferred against its **closed, monomorphic** signature;
earlier generated names and the current recursive binding are in scope.
Unbound names, mismatched types, invalid nominal types, missing/extra
definitions, duplicate names and unsupported polymorphic contracts fail.

`GeneratedDeclarationValidator.validateTyped` accepts the same inputs
and returns the unchanged generated Syntax on success. Its optional
`SourceSpan` argument adds call-site line and column to errors.
`Vm.compileCheckedGenerated` compiles validated output through the normal
self-hosted Nail compiler. There is no new bytecode instruction or syntax
form. This is not a public arbitrary procedural macro system, and it
does not promise sound checking of polymorphic generated signatures.

---

# v0.26: Optional source maps and lexical binding identities

The host parser exposes token coordinates and external AST/source mapping.
A separate analysis resolves lexical references to stable per-program IDs.
Macro-expanded forms preserve original arguments and outer call-site ranges.
No change to the expression AST, runtime data model, or bootstrap bytecode.
Self-hosted parser spans, provenance for every generated child expression and
declaration signature validation remain out of scope.

---

# v0.25 delta: record declaration expansion

`expandRecordDeclarations : Syntax -> Syntax` maps a parser-validated Program to
`RecordExpansion [sourceProgram, runtimeProgram]`. Non-Program input is returned
unchanged, including parser errors. `recordExpansionSource` and
`recordExpansionRuntime` project the two Programs. They require a valid expansion.

`recordDefinitions : Syntax -> [Syntax]` takes a RecordType and produces constructor
and accessor Define forms, in declaration order. `compileSyntax` performs this pass
after expression macro expansion. The core AST, nominal record types, bytecode and
record primitives are unchanged. The transformer is trusted compiler code, not an
extension point for arbitrary user macros. Original syntax is retained without new
source-position or binding metadata. See README.md for API boundaries.

---

# NailSeed v0.24 — Macro modules

Macro expansion still follows the [0.22 template rules](../v0.22/SPEC.md).
This release adds two top-level directives.

```nail
import macroName from moduleName ;
export macroName ;
```

- Module names are identifiers. The resolver maps an identifier to source
  text. PHP's `--macro-dir DIR` option maps it to `DIR/moduleName.nail`.
  The resolver is explicit. There is no automatic working-directory lookup.
- A macro module contains macro declarations, imports, and exports. An export
  names a local macro already declared. Other macros are private. Runtime
  declarations and re-exports are rejected.
- Imports are ordered. An imported macro keeps the macro scope it had at
  declaration, including private macros and imports. The consumer's lexical
  bindings do not affect generated binders or free global references.
- Runtime names referenced by a template must be available in the consumer's
  global environment. Import only brings in macro definitions.
- Resolution is cached for a compilation and rejects cycles, missing modules,
  unavailable exports and duplicate imports. The same resolver can serve a
  host parser, the Nail parser and the bytecode-only bootstrap. Directives
  are removed before checking or bytecode generation.

The standard JavaScript API takes the optional resolver as its second argument
to `expand`, `runPlain`, `runPlainWithNail`, `check`, and `preview`.
The bootstrap runtime accepts it on `compile`, `run`, and `runPlain`.
The PHP bootstrap CLI also accepts `--macro-dir DIR`.
