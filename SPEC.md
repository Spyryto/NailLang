# v0.49 — Finite named n-ary relations and module ABI v3

- Header: `nail 0.49 ;` (previous modern sources 0.45–0.48 remain accepted).
- Declaration: `Constraint : T1 ... Tn Result ;` with 1 ≤ n ≤ 16, 1–128 rows per name; every row has the same arity and the parameter tuple functionally determines the result type. Duplicate parameter tuples are rejected even if their results happen to agree.
- Function: `def fn p1 ... pn : Constraint = body ;`. The body is checked separately for each concrete signature; direct, fully applied calls resolve from all argument types alone. All types in a row must be concrete; no implicit number conversion, automatic operator-polymorphism inference, first-class overloaded values, or higher-order constraints.
- Relations are static metadata: both Haxe and Nail-written source compilers erase the declarations/annotations and generate identical ordinary bytecode, leaving the runtime dispatch unchanged.
- Module ABI: `nailseed.runtime-module.v3` with `numericAbi: "int-ratio-float.v1"` and `relationAbi: "finite-relations.v1"` for constrained imports/exports. The v3 interface carries canonicalized typed rows; the reader validates them against the signature and rejects incompatible or downgraded interfaces. `ModuleLinker.compilePublic` accepts explicit `relation` on an import and inferred verified relation metadata on an export. The current runtime uses runtime-module.v3 for all modern interfaces, including unconstrained ones. Modern v2 images remain available only through historical tagged toolchains.
- The module source language, numeric ABI, portable module image format and bootstrap compiler image version are independently tracked. The module boundary is static and first-order; linking cannot perform new type inference.

---

# v0.48 — Numeric runtime module ABI, separate from source version

## Distinct, explicit version boundaries

- Nail source version: `nail 0.48 ;`. The v0.48 VM still accepts compatible
  `0.45`, `0.46` and `0.47` sources.
- Numeric ABI: `int-ratio-float.v1`. No implicit Float conversions; the
  underlying types remain exactly `Int`, `Ratio`, `Float`.
- Separately compiled module image: `nailseed.runtime-module.v2` with
  `numericAbi`, `sourceVersion`, canonical imports and exports, and
  nested `nailseed.postfix-image.v2` bytecode.
- Self-hosted compiler image: `nailseed.postfix-image.v2` and its own
  `languageVersion: "0.48"`. The module and compiler version numbers
  are not conflated.

Legacy module images `runtime-module.v1` remain decodable with legacy
numeric dialect `0.27` or `0.29`. Historically v0.48 introduced modern
v2 images; the current toolchain instead emits and decodes modern v3
images. A modern v3 image must not carry legacy metadata; a v1 image
cannot pretend to be modern by relabeling its bytecode. The decoder rejects a legacy `ExactNumber` leaf inside
modern bytecode and modern `Int`/`Ratio` leaves inside legacy images.

The linker requires equal numeric ABIs across each runtime import edge;
compatible 0.45-0.48 source revisions share the same modern ABI. Link-time
signature equality is strict. Compile-time manifests also reject all
recursive occurrences of legacy `TNumber`/`TExact` in modern public
interfaces, including nested functions, vectors, records and polymorphic
scheme bodies.

All three compiler entry points (`compile`, `compileInferred`,
`compilePublic`) independently check source with `TypeChecker`,
compare the Nail-written compiler's bytecode against Haxe's reference
compiler and produce image v2 only after that proof. Source-free linking
does not need the parser.

## Deliberate boundaries

- `Div`, `Add`, `Sub`, `Mul` relations remain closed, checked and
  explicitly declared in individual source files (choice B). A generic
  constrained function cannot yet cross a module boundary: its
  relation-aware signature is not representable in the current HM
  `TypeScheme` or module manifests. Exports reject, rather than
  silently erase, such a constraint.
- `ModuleImage` is not an authenticity mechanism. Trusted signatures,
  hashes, and capability grants remain the host responsibility.
- The v0.48 runtime retains compatibility code paths for historical
  `Number` and `Exact` sources, images and tests. They are **not** used
  by the modern ABI. Removing them from general-purpose distributions
  requires migrating those users first, not breaking working artifacts.

---

# v0.47 — Versioned official compiler bootstrap

The **production** bootstrap is now compiled from:
```nail
nail 0.47 ;
# followed by stdlib.nail
```

It uses Int/Ratio/Float semantics within all Nail-written compiler and
standard library definitions. The Haxe stage zero and Nail-written
stages one/two must produce identical canonical structured bytecode.
`haxe seed-image.hxml` produces the modern stage-zero image;
`haxe rebootstrap-image.hxml` verifies and emits a modern self image.

The **bootstrap-image format version** is now deliberately distinct:
`nailseed.postfix-image.v2` with `languageVersion: "0.47"`.
Old source-free VMs reject this envelope by their format check.
The current decoder checks both structure and compiler-source version
and rejects legacy ExactNumber literal leaves in a modern image.
Legacy v1 and v2-exact formats remain accepted only along older
compatibility/module APIs, not as the published bootstrap image.

The user source language accepts compatible `nail 0.45 ;`,
`nail 0.46 ;` and `nail 0.47 ;` programs; no dialect switch comments
are needed for new programs. `Int`/ `Ratio`/ `Float` semantics and
explicit `: Div`, `: Add`, `: Sub`, `: Mul` constraints remain
unchanged.

Distributions: the standard JS/PHP runtime remains available; an
**additional** source-free `boot` JS/PHP variant embeds the modern
Nail-written compiler and image and omits the source parser.
The JSON compiler image is separately downloadable.

**Transitional boundary:** old unversioned source code and old
compiled-module `Number`/`Exact` ABIs still use compatibility code.
This release does not claim that all legacy numeric primitive paths
have been deleted. Constrained numeric type checking remains a
separate TypeChecker API, not a promise of runtime enforcement.

---

# v0.46 — Closed arithmetic relations and modern bootstrap proof

Language version is an explicit declaration, not a comment:
`nail 0.46 ;`. A v0.46 runtime also accepts `nail 0.45 ;` since the
v0.45 numerical semantics are unchanged. Other future versions are
rejected. Number representation and bytecode format are independent
of the language version token.

Four closed binary type relations are now supported:
`Div : Int Int Ratio ;`, `Add : Int Int Int ;`,
`Sub : Int Int Int ;`, `Mul : Int Int Int ;` and further
`Int/Ratio`, `Ratio/Int`, `Ratio/Ratio`, `Float/Float` rows.
The relation `Div` returns `Ratio` for `Int/Int`; the other
three return `Int` for `Int/Int`. No implicit Float coercion.
A definition `def f x y : Add = x + y ;` is checked once per declared
signature and only direct fully-applied calls are supported.
The checker never infers overload constraints absent an explicit
relation annotation (choice B). Relations are not Haskell typeclasses
and do not generate user-defined runtime implementations.

Haxe reference parser and Nail-written parser validate and erase
static relation rows before emitting bytecode. The standalone
source-free VM uses exactly the same numeric runtime primitives.

Migration checkpoint: `modern-bootstrap-test-interp.hxml` constructs
an image of the **entire** stdlib compiled with `nail 0.46 ;`,
then checks fixed point parity with Nail's own compiler. Legacy
bootstrap remains in distributions until all historical tests and
module ABI users have been migrated; no two complete sets of old
language interpreters are claimed to be required for a future release.

---

# v0.45 — First-class numeric domains and source-version declaration

The user-visible syntax is `nail 0.45 ;` at the start of a program.
It is a declaration (not a comment). Unsupported language versions are
rejected rather than reinterpreted as a numeric mode. In v0.45,
the new syntax is selected only by that declaration; unversioned legacy
bootstrap sources remain unaffected until the entire Nail-written stdlib
can be moved.

**Numerics:** integer tokens are `Int` (arbitrary precision via FastNumber),
decimal tokens are `Float` (IEEE-754 binary64), division of two integers
produces `Ratio` (arbitrary exact rational). Mixed Int/Ratio arithmetic
uses Ratio; mixing Float with either exact domain is rejected at both
type-check and primitive runtime level. Explicit conversions are `toRatio`,
`toFloat`, `intFromText` and `ratioFromText`.

The relation syntax (erased before bytecode execution) is:

```nail
Div : Int Int Ratio ;
Div : Ratio Ratio Ratio ;
Div : Float Float Float ;
Div : Int Ratio Ratio ;
Div : Ratio Int Ratio ;

def divide x y : Div = x / y ;
```

The five listed rows are supported by the builtin VM arithmetic. The
checker validates rows, rejects contradictory/duplicate combinations and
allows a file to list a subset. If no row declarations are present,
the five builtin rows are used. A declared function must statically type
check under each allowed row; this is not a full typeclass system, and
there are no user-defined runtime instances.

**Choice B:** Numeric operator constraints are not generalized implicitly.
A function that abstracts over unknown numeric input types must
annotate `: Div`; otherwise the typechecker rejects the unresolved
operator constraint. There are no implicit exact/Float conversions.

**Runtime:** Separate literal tags `Int` and `Ratio` preserve the
semantic distinction on both AST and structured bytecode. An Int remains
an Int even when very large; an integral Ratio remains a Ratio. Both
reuse FastNumber's small-int and reduced big-rational infrastructure.
The compiler written in Nail recognizes `nail 0.45 ;`, erases type
relations, and applies a first-class Syntax rewrite. Haxe reference
compilation and source-free bootstrap must produce identical bytecode
on all supported targets.

**Current scope:** The old Number/Exact bootstrap semantics still exist
internally; these are not exposed as the numeric defaults of 0.45
source. This release does not introduce a full module ABI for the new
types, generic constrained higher-order function passing, or
backward-compatible source interpretation in a 0.45-only VM.
Type checking is a separate opt-in host API before compile-only execution.

---

# v0.44 — Explicit, closed binary type relation prototype

## Decision

Nail uses **explicitly declared** operator-constrained polymorphism,
not automatic generalization of numerically overloaded operators (choice B).
The user's concise syntax keeps the value binders separate from the type
constraint:

```nail
def divide x y : Div = x / y ;
```

The two arguments `x` and `y` are ordinary Nail value binders.
`: Div` authorizes the **closed** set of concrete function signatures
listed below, and the checker verifies the same function body independently
under each signature. It does not introduce new binders and is erased
before bytecode generation. A definition without `: Div` remains
monomorphic for division, as before.

## Initial implementation boundary

Only the already-shipped numeric types participate in v0.44:

```text
Div : Number Number Number
Div : Exact  Exact  Exact
```

These rows document the **internal fixed whitelist**: they are *not*
yet source declarations. `Number` denotes the old Float domain, while
`Exact` denotes the v0.29 exact rational domain. There is **no**
`Int`, `Ratio` or standalone `Float` type in this release, nor
a syntactic `Div : Int Int Ratio ;` definition. The migration to the
user-proposed types and table is the next independent language task.
This iteration proves source annotation, checking and erasure without
coupling them to the numeric redesign.

`divide 9 2` resolves to Number; `divide (exactFromText " 3 ")`
`(exactFromText " 2 ")` resolves to Exact. Mixed domains fail statically
and at runtime. The slash primitive dispatches by the runtime value
variant; no implicit conversion is performed.

## Fail-closed boundaries

- A constrained declaration must have exactly two parameters, use `Div`,
  and belong to the default source dialect. The legacy exact-header
  dialect cannot declare a constrained function in this step.
- The checker verifies the body under **every** supported row. For
  example `def divide x y : Div = x + y` is rejected because it does
  not respect both signatures without overloading of `+`.
- Fully applied direct calls `divide x y` are supported. Partially
  applied calls, function values, polymorphic recursion and generic
  unconstrained wrappers cannot be checked and are explicitly rejected.
- The type checker remembers declared relations across successful
  incremental checks and copies, without committing declarations
  from a failed batch.
- Public module image ABIs do not yet represent named relations:
  exporting an annotated function through an HM scheme is rejected,
  rather than silently dropping its constraint.
- **Compile-only** APIs do not perform Haxe static type-checking.
  Untrusted source must be checked explicitly with `TypeChecker.check`.
  Bootstrapped compilation erases `: Div` and generates exactly the same
  runtime closure bytecode as an unannotated function. No relation
  metadata travels with the current standalone bytecode ABI.

## Next milestones

1. Replace legacy numeric dialect switching with `Int`, `Ratio`,
   and `Float` as stable, distinct types, with no implicit exact-to-Float
   conversions. Define `Int / Int -> Ratio` independent of result value.
2. Promote relation rows into explicitly checked source declarations or
   versioned built-in signatures; reject duplicate input-pair rows.
3. Support relation-aware higher-order functions and fully sound module
   serialization after determining the desired elaboration strategy.
4. Introduce an explicit Nail source-language version separate from
   numeric type selection and bytecode-envelope version.

---

# v0.43 delta — Exact-rational integer rounding

## Why

The opt-in numeric dialect `# nail: 0.29` already represents integers
and rational values exactly using a small-integer fast path and normalized
arbitrary-precision fractions. Converting to a binary Float to find a
floor, ceiling or rounded tick would silently lose precision and defeat
that representation. This release adds five pure functions **without
changing the source dialect, grammar, core AST, bytecode, or module ABI**.

## Typed functions

| Name | Signature | Semantics |
| --- | --- | --- |
| `exactFloor` | `Exact -> Exact` | Greatest integer not exceeding input |
| `exactCeil` | `Exact -> Exact` | Least integer not below input |
| `exactTruncate` | `Exact -> Exact` | Integer part toward zero |
| `exactRoundEven` | `Exact -> Exact` | Nearest integer; halfway selects even |
| `exactIsInteger` | `Exact -> Bool` | True iff reduced denominator equals 1 |

All results from the first four functions remain `Exact`, not `Number`
and not a new integer subtype. The TypeChecker rejects Float arguments;
no hidden type widening or cross-dialect conversion is permitted.
`exactFromText` is an existing explicit conversion available to callers
in the default dialect as well.

## Numerical algorithm

For an exact fraction `n / d` with unsigned positive magnitudes and a
separate sign, compute `q, r = divmod(n,d)` using `BigNat`:
- Truncate: `q`, with the original sign.
- Floor: on negative non-integrals, `-(q+1)`; otherwise `q`.
- Ceil: on positive non-integrals, `q+1`; otherwise `-q`.
- Half-even: compare `2r` to `d`; on equality choose `q` if its
  decimal units digit is even, or `q+1` if odd; restore original sign.

Normalized exact integer input returns unchanged, including the
small-integer fast representation. Zero has no negative sign.
Work budgets and output digit budgets are enforced. The algorithm never
converts the fraction to IEEE-754 Float, works on all Haxe/JS/PHP backends
and rejects an Approximate-valued host input.

## Invariants and compatibility

- The legacy `Number` (Float) dialect remains unchanged.
- The exact-number source header is still `# nail: 0.29`; the runtime
  version advancing to v0.43 does not reassign the meaning of that header.
- Haxe AST evaluator, reference bytecode compiler, Nail-written compiler,
  source-free bootstrap and Haxe/Node/PHP runtimes must agree.
- Round-to-nearest has **one documented tie rule**; there is no
  platform-specific `Math.round` or rounding-mode default.

## Tests

`haxe exact-rounding-test-interp.hxml`, followed by the JS and PHP
variants, exercise positive/negative fractions, exact half ties, large
integers, type-checking, rejected Float values, serialization and the
self-hosted compiler fixed point. The release workflow runs the same tests
before publishing distributions.

---

# v0.31 delta — Independently compiled runtime modules

## Module unit contract

A source module is an ordinary Nail program plus a separate **host manifest**
consisting of a module name, source text, declared import dependencies and
declared export signatures. Runtime modules are distinct from the pre-existing
**compile-time macro modules**: macro `import/export` source forms keep their
original syntax and meaning.

`SourceModuleSpec` contains the source and fully qualified imports
`{module, symbol, alias, type:NType}`; exports are
`{name, type:NType}`. The first module ABI deliberately admits only closed
monomorphic signatures composed of primitive, function, list and vector
types. Public nominal and polymorphic type exports are deferred.

## Compile independently

1. Validate identifiers and aliases, reject missing or repeated manifest
   entries, top-level `Evaluate` expressions and local shadowing of imports.
   Module source has no ambient dependency imports.
2. Create a fresh TypeChecker and install *only* explicit import aliases with
   the corresponding closed types. Check the whole program transactionally.
3. Every export must name a module-local `Define` and its inferred signature
   must be exactly the declared public signature. An export may not re-export
   an imported alias implicitly.
4. Compile with both independent backends: the Haxe reference compiler and
   the Nail-written **source-free BootRuntime**. Require byte-for-byte
   canonical structured-bytecode equivalence.
5. Serialize a self-contained `nailseed.runtime-module.v1` image containing
   the module name, `sourceDialect`, canonical import/export signatures, and
   a versioned Bytecode image. **The source is absent from the artifact.**

Compilation is per-module and can happen in arbitrary order. The linker
never calls the Haxe parser, Nail source parser, type inference or compiler.

## Link independently

`ModuleLinker.linkImages` decodes compiled images, validates their interfaces
and permitted top-level bytecode forms, and resolves the dependency graph
topologically. Cyclic dependencies, unknown modules, missing or unexported
symbols, signature mismatch, duplicate public names and alias collisions
are errors. The module graph is bounded in size and depth.

Each module runs exactly once in its **own ByteVm root**. Only explicitly
imported symbols are bound into that root before module initialization.
Exported functions retain lexical closures over their **defining module's**
environment. Module runtime instances are private; `ModuleBundle.read`
and `invoke` check the public export set rather than permitting arbitrary
global lookups.

`0.27`/default floating `Number` and `0.29` exact-number source
dialects remain separate. A runtime dependency edge between the two is
rejected, even if its imported name or desired signature appears similar.
An exact module uses the v2-exact image envelope; the legacy module uses
the legacy v1 bootstrap format. No JSON numeric field transports a large
exact fraction.

## Security and compatibility bounds

Module images are **trusted build outputs**, not cryptographically signed
artifacts. Decoding validates the interface and bytecode structure and
prevents accidental version confusion, but type safety against an
arbitrarily tampered/replaced bytecode payload requires source provenance or
authenticated artifacts. The module runtime does not expose host I/O.

This milestone is a working host API, **not new Nail source grammar**:
runtime imports/exports are supplied as manifest data. Future explicit
source-level interface syntax should lower to this same loader/linker API.
Public nominal types, polymorphic promises, controlled recursion between
modules and generative export inference require subsequent specification.
The old macro module API is unchanged.

## Acceptance tests

- A three-module legacy application compiles each file independently and
  executes correctly after linking images out of order.
- A two-module exact-number music clock computes `30720/97` seconds for
  128 four-beat bars at 97 BPM without Float conversion.
- Private symbols cannot be called/imported, import signatures are checked,
  and cycles, missing modules, duplicates, aliases and dialect mismatch fail.
- Haxe/JavaScript/PHP agree on results and inferred interfaces; the complete
  inherited v0.30 bootstrap/fixed-point tests stay green.

---

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
