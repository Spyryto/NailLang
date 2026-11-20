# Structural row-scheme ABI: canonical wire preview (not released)

**Status:** design-and-test experiment only. This preview is not a Nail
language version, a module-image version, or an exported type interface.
`ModuleImage` and `PublicSchemeImage` continue to reject open structural
rows and unknown scheme fields. The test-only reference validator is
`src/nail/RowSchemePreview.hx`; no compiler, linker, or VM entry point
calls it.

## Why the existing v3 scheme cannot simply gain a row field

The existing portable scheme has exactly `term`, `quantified`, and
`comparable`. A type such as “a record with `x: Int` and other
fields `r`” implies the **negative obligation** `x ∉ r`. Dropping it
when importing a polymorphic function is unsound: the caller could insert
a second field named `x` into the residual tail.

The Nail-owned HM checker already tracks this obligation through its
internal `TCRowQuant` metadata, but that is not public ABI evidence.
The proof-of-concept below proposes an explicitly versioned wire shape,
without yet changing the public module envelope.

A checked-definition-only *reference producer* is available through
`TypeChecker.experimentalCheckedRowPreview(name)`. It is callable only
after the Haxe checker has successfully committed an explicitly defined
modern source symbol; it canonicalizes its inferred type variables by
first occurrence and derives mandatory `lacks` sets from the flattened
row prefixes. It does not export a module interface or prove that an
arbitrary provider obeys its inferred type, and it does not yet translate
the Nail-written checker's independent `TCRowQuant` ledger.

### Nail-authored canonical Syntax evidence (new experiment)

`tcCanonicalRowEvidence scheme` runs **in Nail bytecode** on the same
portable VM as the independent HM checker. It canonicalizes structural
field order, alpha-renames quantified variables, and merges negative field
obligations from both the inferred type shape and `TCRowQuant` sidecars.
It rejects free/phantom quantifiers, duplicate fields, mixed ordinary/row
variable kinds, Eq on a row tail, and guards that cannot be represented by
the visible quantified row tail.

The result is `Ok(TCWireScheme Syntax)` or `Error(Text)`. A small
`NailRowEvidenceAdapter` converts this **already canonical Syntax tree**
into the preview JSON and passes it to `RowSchemePreview` for independent
format validation. The adapter must not perform type inference, field
sorting, or invent negative evidence; parity tests compare the resulting
bytes with the Haxe checked-source producer when both support the same
scheme. A separate test verifies the Nail-only ledger can add a legitimate
`lacks reserved` qualifier absent from the visible type prefix.

### Transactional checked-source schemes

The Nail checker now has a **separate, opt-in** entry point,
`tcCheckSourceSchemes source`, returning
`Ok(TCCheckedSchemes [TCChecked, TCExportSchemes])` only after the
**entire** source program has typechecked. `TCExportSchemes` contains
only schemes for explicitly visible `Define`/`AnnotatedDefine` forms
from the checked syntax; private names created by macro/compiler lowering
are filtered out. It carries the original generalized `TCScheme`
(including `TCRowQuant`) from the *same inference pass*, not a
reconstruction from flattened result types.

`tcCanonicalCheckedDefinition source name` checks the source once,
looks up the requested definition in that successful snapshot and
invokes Nail's `tcCanonicalRowEvidence` on the exact recovered scheme.
Unknown or unsupported exports return `Error`. If a later form fails
the typecheck, the entire operation returns `Error` with **no
partial scheme data**.

Existing `tcCheckSource`, `tcCheckSyntax` and traced check APIs
continue returning `TCChecked` on success: their result shape does not
change. The new snapshot exposes neither bytecode nor a public
module interface. It is intentionally an opt-in, type-only API.

### Selected multi-definition interface preview

`tcCanonicalCheckedInterface source [name, ...]` is a private,
**opt-in** Nail function for building a deterministic interface preview
over a chosen subset of verified top-level definitions. It executes
`tcCheckSourceSchemes` **once**, selects only names present in the
successful source-level `TCExportSchemes`, and canonicalizes each
scheme in Nail via `tcCanonicalRowEvidence`. Selection order and
source declaration order do not affect its output.

The result is `Ok(TCWireInterface [TCWireExports])` or `Error(Text)`.
Duplicate, missing, private, invalid or unsupported names reject the
**entire** interface; a later source type error never leaks earlier
definition schemes. The selector deliberately does **not** read public
module `export` declarations: it accepts an explicit list of requested
definitions for the experiment only.

`NailRowInterfacePreview.encode` is an isolated Haxe serializer
and strict decoder. The wrapper format is:

```json
["naillang.interface.preview.v0",
  [["id", ["naillang.row-scheme.preview.v0", ["fn", ["var", 0], ["var", 0]], [0], [], []]]]]
```

Entries have unique, strictly increasing ASCII identifier names and
each nested scheme must satisfy `RowSchemePreview` validation.
The adapter cannot infer types, silently sort entries, generate lacks
constraints or authorize linked imports. It only serializes completed
Nail-owned canonical Syntax and validates the resulting bytes.

This is **not** the public module ABI, a signed module interface or a
promise that the runtime implementation matches a manually provided
signature. Trusted import/linking, external module exports, nominal
types and binding freshness remain future stages.

### Explicit value exports (opt-in source preview)

A separate entry point, `tcCanonicalDeclaredInterface source`, accepts
modern, versioned Nail source with explicit declarations such as:

```nail
nail 0.54 ;
def readField r = r . x ;
export readField ;
```

In **this preview only**, `export readField ;` declares that the verified
source definition should appear in the canonical interface. The parser
already recognizes `export name ;` as a macro-module directive; the
opt-in function recognizes that parsed marker as a typed *value* export,
removes the directive **before** macro expansion, verifies the complete
remaining program and selects only the declared names from its
transactional scheme snapshot. `export` may precede the definition; the
type checker still traverses source forms in the original order.

This **does not reassign the meaning of `export` in the ordinary Nail
compiler or in macro modules**. The existing checked-source API continues
to reject a typed top-level value export directive outside this
experimental entry point. The type interface preview rejects missing
definitions, duplicate exports, a source type error after a definition,
unsupported types, and any unexpected private bindings without emitting
partial results.

The outcome is the same private `TCWireInterface` Syntax already
implemented for explicit selected-name previews. It can be validated by
`NailRowInterfacePreview`, but cannot be used as an import contract by
`ModuleLinker`, and has **no effect** on the public v3 ABI.

### Validated interface consumption (stacked experiment)

A new private consumer can read the preview format, but **it does not
link or execute an imported module**. The sequence is intentionally
two-stage:

1. `NailRowInterfacePreview.decodeSyntax(json)` checks the canonical
   external JSON (including per-scheme quantifiers and all `lacks`
   requirements) and translates its data, without inference, into the
   existing `TCWireInterface` Syntax IR. Unknown type constructors
   unsupported by the Nail importer are rejected.
2. `tcImportWireInterface wireSyntax`, implemented in Nail, converts
   verified wire schemes to private `TCScheme` values with `TCRowQuant`
   obligations. On each use, `tcImportWireInstantiate request` delegates
   to the **same Nail HM `tcInstantiate`** used by local definitions:
   it freshens quantified variables together, applies `Eq` and replays
   negative row constraints into the substitution ledger. The caller must
   thread the returned seed and substitutions to avoid accidental reuse
   of variable names.

Imported `lacks` labels do not carry field *types*. The private
`TCRowQuant` reconstruction therefore uses `TCMissing` in those
guard-only field slots: `tcCheckRowShape` observes their **names**, not
their payload types. This marker never appears in a function's inferred
type or the public module scheme.

Cross-target regressions verify two distinct instantiations, failed late
bindings of an existing prefix field `x`, rejection of an *extra*
`lacks reserved` obligation arriving only via wire metadata, acceptance
of unrelated `z`, unknown imports, and strict tamper rejection before
Nail receives the tree.

The result **is not a trusted module import**. A validated format does
not attest that the supplier implementation has the claimed type. No
public `ModuleImage` version, runtime binding, import declaration, or
linker call path invokes this consumer. Provider identity, signed/hash-
bound interfaces, import-name scoping, and real module linkage require
a separate correctness gate.

## Preview wire grammar

The entire preview is a JSON **array**, to avoid object-key ordering
differences across Haxe, JavaScript and PHP:

```text
Scheme := [ "naillang.row-scheme.preview.v0", Type, Quantifiers, Eq, Lacks ]
Quantifiers := [ 0, 1, ..., n-1 ]
Eq := [ quantifiedVariableId, ... ]
Lacks := [ [ tailVariableId, [ absentFieldName, ... ] ], ... ]

Type :=
    [ "Int" | "Ratio" | "Float" | "Number" | "Exact"
      | "Bool" | "Text" | "Syntax" ]
  | [ "var", quantifiedVariableId ]
  | [ "fn", Type, Type ]
  | [ "list", Type ]
  | [ "vector", Type ]
  | [ "row", [ [fieldName, Type], ... ], null | [ "var", tailId ] ]
```

Example: the function type is a record requiring `x: Int` and `y: Text`
(with an open tail `r`), returning a list of `a`. The `a` type must
also be comparable:

```json
[
  "naillang.row-scheme.preview.v0",
  ["fn",
    ["row", [["x", ["Int"]], ["y", ["Text"]]], ["var", 0]],
    ["list", ["var", 1]]],
  [0, 1],
  [1],
  [[0, ["x", "y"]]]
]
```

## Canonicality and soundness rules

1. **Quantifiers:** numeric variable IDs must be exactly `0..n-1`,
   without missing or unused IDs (limit: 64). A future producer is
   responsible for alpha-renaming arbitrary internal variables to these
   IDs. The current preview validator does **not** perform inference or
   alpha-renaming for callers.
2. **Rows:** fields must be nonempty, unique, valid ASCII identifiers
   and strictly ordered by name. A row tail is either `null` (closed)
   or an explicitly quantified variable (open). The preview uses one
   flat row node, not a chain of duplicateable field extensions.
3. **Negative evidence:** every open tail requires a `Lacks` entry,
   whose sorted, unique absent-name set contains **every field of every
   row prefix using that tail**. Additional negative obligations are
   allowed. A `Lacks` entry for a variable never used as an open tail
   is invalid. Thus no row qualifier can be discarded accidentally.
4. **Eq and kind evidence:** comparable quantifier IDs must be in
   scope, strictly increasing and unique. A quantified variable used as
   an open row tail cannot also be an ordinary type variable or be
   directly Eq-qualified. No unconstrained/free variables may appear
   anywhere inside the type.
5. **Limits:** maximum nested type depth 48, 2048 type nodes, 128
   fields per row or `Lacks` entry, 64 quantified variables; unknown
   tags, nested row-tail expressions, nominal types, unsupported
   relations, noncanonical JSON whitespace and inconsistent constraints
   all fail closed.
6. **Wire canonicality:** arrays use a fixed positional order. Text
   must equal its JSON serialization byte-for-byte; do not rely on
   potentially unstable JSON object-key ordering.

## What is deliberately not implemented

- No public `runtime-module.v4` version, module signature change,
  exported row schemes, linker support or release commitment.
- No conversion of the Nail-written checker’s `TCRowQuant` sidecar
  into independently attested wire evidence. The Haxe reference producer
  derives obligations visible in its checked row prefixes but does not
  capture negative constraints that exist **only** in the Nail checker’s
  substitution ledger.
- No nominal type identities, relation-overload ABI, recursive row
  aliases, generalized user-authored row constraints, or independent
  proof of `Eq` dictionary semantics.
- No import-side row-variable instantiation. This preview validates
  evidence, but it does **not** establish that the imported provider
  implementation satisfies that evidence.

Before enabling a real public row ABI, we need a **trusted encoder** from
verified types (with alpha-normalization), a strict importer that freshens
all quantified variables and `Lacks` obligations together, stable module
signatures and signed-interface compatibility checks, and differential
compiler/VM tests that demonstrate rejection of late duplicate labels.

## Reproducible validator tests

The preview runs on all three current compiler targets without requiring
public modules to understand its format:

```sh
haxe row-scheme-preview-test-interp.hxml
haxe row-scheme-preview-test-js.hxml
node build/tests/row-scheme-preview.js
haxe row-scheme-preview-test-php.hxml
php build/tests/php-row-scheme-preview/index.php
```

The CI harness adds the `row-scheme-preview` suite to the existing
cross-target regression matrix. Malformed, tampered, out-of-order, too-deep,
free-variable, duplicate-label, orphan-lacks, missing-lacks, and
noncanonical JSON fixtures must all be rejected.

The same suite exercises checked-source-derived schemes via the Haxe
reference checker, compares alpha-equivalent sources after unrelated
binder allocation, and verifies that the ordinary public module ABI still
refuses open structural exports. The producer path is experimental and
does not accept a caller-supplied `TypeScheme` through its checked entry
point.
