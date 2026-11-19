# Nail-written type checker — staged dogfooding experiment

**Status:** stacked experimental draft PR #29 (based on the contextual DSL
prototype in PR #28). Neither PR changes the released NailLang 0.54.

## Purpose

Implement the type checker *in Nail*, not via a host function which delegates
to the existing Haxe `TypeChecker`. Keep the Haxe implementation as an
independent reference until parity and diagnostics can be verified.

The first checker lives in `stdlib.nail`, with functions prefixed `tc`.
It is compiled to ordinary Nail bytecode during the normal bootstrap. The
existing VM and primitive boundary are unchanged.

## Representation

| Item | First-class Nail representation |
| --- | --- |
| Type variable | `syntaxLeaf "TCVar" id` |
| Primitive type | `syntaxLeaf "TCBase" name` |
| Function / list | `syntaxNode "TCFun"/"TCList"` |
| Closed structural record | `syntaxNode "TCStruct" fields` |
| Open structural requirement | `syntaxNode "TCRowField" [name, type, rest]` |
| Nominal record/sum | `syntaxNode "TCNominal" [kind, owner, typeArguments]` |
| Polymorphic scheme | `syntaxNode "TCScheme" [term, quantifiers, EqQuantifiers]` |
| Substitutions / environments | Persistent association lists |
| Inference outcome | `Ok(TCChecked)` or `Error(Text)` |

Type variables are generated using a deterministic textual counter. The
algorithm is purely functional: substitutions and the next variable label
are returned through ordinary `Syntax` data rather than mutable VM state.
Unification performs an **occurs check** to reject infinite types.

## Present scope

- Full *five-case core expression* traversal: `Var`, `Literal`,
  `Lambda`, `Apply`, `If`
- Hindley–Milner unification, lexical environments, generalization of
  direct `let`, fresh instantiation, sequential recursive `def`
- Primitive `Int`, `Ratio`, `Number`, `Exact`, `Bool`, `Text`
  and type-variable lists
- Closed anonymous record fields and **limited open-row projection** of
  unknown record parameters, including width matching against known records
- **Nominal record constructors**, typed positional and named-field creation,
  generic parameters and field accessors, with nominal identity enforced on
  unification; an unbound receiver's field selects a nominal owner only
  when that field is unique across declared records
- **Algebraic sum constructors**, including zero-field cases and polymorphic
  variants (for example `type Option a = None | Some a`); distinct sum
  owners remain distinct, with predicate and positional accessor signatures
- **Exhaustive list and nominal sum patterns** in `match ... with` and
  `function | ...`: the Nail checker recognizes the parser's private
  lowering, checks each constructor's owner and binding arity, rejects
  missing cases and mixed owners, then uses ordinary HM inference for the
  bound values and branch results. No new core AST constructor or VM opcode
- **Optional parameter and value annotations**, structural type aliases
  `type Html = { h2 : Text Text , div : Text Text }`, required-field
  validation with allowance for additional implementation fields
- **Finite modern arithmetic**: direct binary `+`, `-`, `*`, `/`
  with concrete `Int`, `Ratio`, `Float` operand pairs and exact
  result domains; unresolved or mixed operands fail closed
- **Qualified polymorphic equality** `==` and `!=`: a free
  variable receives an `Eq` requirement, retained across unification,
  generalization, and fresh scheme instantiation. Primitive types,
  homogeneous lists and closed structural records are checked recursively;
  equality involving functions is rejected
- **Named finite relations of arity 1–16**, including `Add`, `Div`,
  `Merge : Text Text Text` and `Join3 : Text Text Text Text`. Each
  constrained function body is checked independently against **every**
  declared row, with input type constraints aligned to its exact parameter
  count. Fully applied calls select the output type from all input types.
  Duplicate tuples and inconsistent row arity are rejected
- A **conservative primitive prelude** for selected text/list operations;
  deliberately not a claim of full 0.54 typing semantics

### API

`tcCheckSyntax program` takes an already lowered `Program` Syntax node,
without parsing or invoking the Haxe checker.

`tcCheckSource source` is an experimental convenience helper which invokes
the **Nail-written** parser in a metadata-preserving mode,
`parseTypedForms`, followed by `modernRewrite` and `tcCheckSyntax`.
It retains `TypeAliasDecl`, `RelationDecl`, and `AnnotatedDefine`
only while checking; ordinary `parseSource` still erases them for execution.
The helper returns `Ok(TCChecked)` with a list of inferred expression
types, or `Error(Text)`. `tcPretty` formats an individual type.

The runtime does **not** automatically run `tcCheckSource` before
`compileSource`. Checking remains opt-in, so the incomplete checker cannot
silently reject or reinterpret supported programs.

### Macro-aware source checking (experimental)

`tcCheckSource` now keeps structural aliases, relation rows and annotated
definitions in a private Nail-side metadata table while the existing
`macroExpandSyntax` primitive expands **local template macro declarations**
exactly once. The checker then restores static metadata, rewrites numeric
syntax and infers the expanded program in Nail. The macro-expansion primitive
is still implemented in Haxe; it performs no type inference and never calls
the Haxe `TypeChecker`.

Template-generated free references (`#macro_global_...`) are looked up through
private *global-only* environment entries, so local variables introduced at
a call site cannot capture them. The checker also recognizes the expander's
hygienically renamed match subjects (`#macro_local_...`) and validates
their sum patterns and accessor calls. This does not require new VM opcodes,
a sixth core expression or public syntax for private names.

Macro imports requiring an external module resolver, macro-aware error
provenance, full compiler pipeline integration and the final typed module ABI
are still outside this experiment.

## Example: explicit contracts and numeric relations

```nail
nail 0.54 ;
type Html = { h2 : Text Text , div : Text Text } ;
def render ( html : Html ) title = html { h2 title } ;
def page = { h2 = fun x -> x , div = fun x -> x , extra = true } ;
render page " Title " ;

Div : Int Int Ratio ;
Div : Float Float Float ;
def divide x y : Div = x / y ;
divide 6 3 ;
divide 6.0 3.0 ;
```

The checker accepts the extra `page.extra` field but rejects missing or
mistyped `h2` or `div`. A numeric relation is a finite set of statically
checked rows, **not** runtime overload dispatch. The receiver and the
overloaded function must have sufficient static information to resolve
their calls. The standard compiler still erases annotations before running
the program on the same VM.

For example, a three-parameter named relation is checked without any
special runtime support:

```nail
Join3 : Text Text Text Text ;
def join3 a b c : Join3 =
  textConcat ( textConcat a b ) c ;
join3 " A " " B " " C " ;
```

The checker handles one through sixteen parameter types (followed by
one result type), and checks arity, input tuple uniqueness and every
constrained definition. Partially applied or higher-order use of these
overloads is still deferred; such cases are rejected explicitly.

A concrete equality expression, such as `[ 1 , 2 ] == [ 1 , 3 ]`,
is checked to produce `Bool`. A polymorphic equality function can now
retain its required qualification, as illustrated by:

```nail
def same x y = x == y ;
same 3 3 ;
same " A " " B " ;
same [ 1 , 2 ] [ 1 , 3 ] ;
```

Each call instantiates a fresh `Eq`-qualified type variable. Unification
propagates the requirement to lists and structural fields; functions still
fail static checking. Internally the requirement lives in the same
persistent binding stream as substitutions (with a disjoint private key),
and the scheme preserves the quantified variables that are comparable.
The compiler does not perform runtime type-class dispatch.

## Example: nominal identity and generic constructors

```nail
type Person { name Text age Int } ;
type Badge { owner Person valid Bool } ;
( Badge { owner = Person " Ada " 35 , valid = true } ) . owner . name ;

type Box a { value a } ;
( Box 21 ) . value ;
( Box true ) . value ;

type Option a = None | Some a ;
Some 3 ;
Some true ;
```

Record constructors and generic sum constructors are checked through
ordinary polymorphic schemes in the lexical type environment. A nominal
record field accessor is resolved to one declared owner when unambiguous;
two owners declaring the same field require a more explicit use or will
raise an ambiguity diagnostic. Nominal identity cannot be forged by
providing the same structural fields. The runtime already lowers all
these declarations to ordinary `Define` forms: the new logic exists only
in the Nail-written type checker.

The generic constructor and pattern tests compare Nail's output with
the separate Haxe checker. Exhaustiveness and destructuring are validated
for the exact private sum-match lowering shape produced by the normal
self-hosted parser, including hygienically renamed macro-generated subjects.
These checks remain opt-in; they do not yet retain full source provenance.
Nominal public-interface ABI validation remains future work.


## Hygienic macro example

```nail
nail 0.54 ;
type Option a = None | Some a ;

macro unwrap x = quote (
  match unquote x with
  | None -> 0
  | Some value -> value
) ;

expand unwrap ( Some 42 ) ;
```

The macro's internal subject is alpha-renamed, and its constructor predicate
and accessor names remain bound to global declarations. The Nail checker
recognizes this lowered pattern and infers `Int`. A missing `None` branch
is reported as a non-exhaustive match. A local variable shadowing a referenced
global function must not capture that function in the generated expression.

## Pattern inference examples

```nail
nail 0.54 ;
type Option a = None | Some a ;
def unwrap = function
  | None -> 0
  | Some value -> value ;
unwrap ( Some 42 ) ;

def firstOr fallback = function
  | [] -> fallback
  | item :: rest -> item ;
firstOr 0 [ 1 , 2 ] ;
```

The nominal match must cover all variants of the same owner. A missing
`None` or `Some`, a constructor from a different sum, or a mismatch between
the declared payload arity and the pattern binders returns `Error(Text)`.
The private `#sumFail` fallback is assigned a polymorphic bottom-like type
**only after** successful coverage validation; it is not exposed as a normal
source-level name. List patterns use existing private list operations with
ordinary polymorphic list signatures. The validation and inference run in
Nail bytecode on Haxe, Node and PHP.

## Structured original-source diagnostics (experimental)

An additional developer-side adapter, `nail.NailSourceAnalysis.analyze(source,
?boot)`, can consume the **Nail-written** checker directly from the source-free
bytecode image. It returns:

- `ok: Bool`, inferred `types: Array<String>` on success
- `diagnostics: Array<{phase, message, span, templateSpan, templateOrigin}>`
  on failure, where `templateOrigin: {sourceId, span}?` identifies even an
  imported template's source
- `span` and `templateSpan` use the pre-existing `SourcePositions.SourceSpan`
  convention: original-source, half-open UTF-16 offsets, 1-based lines/columns

The checker now offers two APIs:

- `tcCheckSource` preserves the prior `Result[Syntax, Text]` contract.
- `tcCheckSourceTraced` returns `Error(TCFault)` with the **same Nail
  error message**, plus a structured expression-child path and failing-form
  trail. Tracing is compiled into ordinary Nail bytecode and adds no core AST
  constructor or VM opcode. The adapter runs this checker **once** per query.

The adapter does **not** call the Haxe `TypeChecker`. It reuses
`SourcePositions.scan` for original UTF-16 coordinates. When a structural
path is available, it optionally uses the pre-existing Haxe
`Parser.parseRaw()` **only as a provenance sidecar**, never for inference or
validation. If the host parser does not understand experimental syntax or the
AST has changed under macro expansion, the mapper falls back conservatively.

For example, with:

```nail
nail 0.54 ;
def broken = if true then missing else missing ;
```

The original scanner sees two `missing` tokens, but Nail's error path
identifies the `then` child of `If`, so the diagnostic points at the
**first** occurrence. Similarly, if two definitions use the same invalid
name, the failing-form trail selects the earlier failing definition. Tests
also cover errors nested in lambdas, function applications and the two operands
of lowered numeric/equality operators.

Local macro calls now have a **two-origin read-only sidecar**:
`SourceProvenance` attaches a precise `expand` token to generated nodes
and independently retains a pair `{sourceId, span}` for each node's
quoted-template origin.
`MacroExpander.forms(input, provenance)` can replay exactly the same
hygienic AST transformation solely for this diagnostic lookup. The runtime
expander, bytecode, canonical Syntax representation and type inference do
not gain new nodes or metadata. Parentheses that merely delimit the quoted
template are stripped from the reported template span only after verifying
a complete balanced wrapper.

This distinguishes **multiple invocations of the same macro** in the same
form, **different macros** in consecutive forms and **nested macro calls**:
the generated error points at its outermost user-authored expansion site,
while `templateSpan` points at the expression in the actual producing
macro. A caller argument substituted via `unquote` keeps its own source
position and has no fabricated template origin.

The optional module-aware entry point is:

```haxe
NailSourceAnalysis.analyze(source, boot, moduleName -> moduleSource, 'src/main.nail');
```

The third argument is a **source resolver** that returns module text by its
logical import key (for example `helpers`). The fourth names the caller's
source. On imported expansions, `span` identifies the caller's `expand`
token; `templateOrigin.sourceId` names the module containing the producing
template, and `templateOrigin.span` uses offsets **in that module's text**.
To prevent accidental cross-file interpretation, `templateSpan` is
`null` for foreign templates, and remains populated for local macros.

**Typed module-aware inference (experimental).** The caller's source is now
parsed directly by the Nail bytecode parser via `tcPrepareTypedSource`.
This returns `TCPreparedMacros`: a Program with non-executable type metadata
temporarily replaced by static placeholders, and the saved metadata.
Haxe's existing hygienic Syntax expander resolves the external macros, while
each imported module is parsed through the Nail `parseSource` function rather
than the Haxe `Parser`. Nail applies `modernRewrite` **before** host macro expansion to both
the prepared caller Program and parsed imported templates. This is essential:
a host Syntax decode/encode pass must not change `1.0` (Float) into `1` (Int)
merely because both have the same numeric value. The `Int` and `Number`
Syntax tags preserve that distinction. Finally Nail's
`tcCheckExpandedTypedTraced` (one two-child Syntax payload) restores aliases,
relation declarations and annotated definitions and runs the Nail checker;
it deliberately does **not** rewrite already-typed numeric literals twice.

Consequently, the module-aware route now preserves **structural aliases,
explicit parameter/value annotations, contextual DSL blocks and 1–16-ary
named type relations**. Validation also checks rejection cases, so an import
cannot silently erase a type restriction. The no-module case continues to
use `tcCheckSourceTraced` and remains unchanged.

This adds no VM opcode, no sixth core expression constructor, and no
Haxe type-checker delegation. Haxe is still used as an import-text
resolver/orchestrator and for the existing *syntactic* macro transformation.
The two syntax paths share the same Nail checker and type rules.

The resolver is cached per analysis request, so the host's syntax expansion
and the provenance replay read each module once. Nested and transitive imports
retain the *actual producing module*, rather than the module through which it
was re-exported. Caller subexpressions inserted using `unquote` continue
to point to the caller's source and have no foreign-template origin.

**Scope boundary:** although parsing, typed metadata preservation
and inference all run in Nail, the hygienic macro *substitution* itself
remains the existing Haxe-based syntax primitive. The source-position
sidecar also uses the optional Haxe parser for diagnostic-only replay,
which may not understand every experimental typed DSL construct. Logical
module names are stable identifiers supplied by imports, **not inferred
filesystem paths**. Missing imports and incompatible module dialects are
reported without made-up source coordinates.

Where a structural path cannot be mapped, locations are restricted to
unambiguous tokens within the failing form, duplicate declarations or an
isolated source pattern. The provenance replay can decline to map
experimental syntax which its parser does not accept. A general unification
failure with no trustworthy generated call site still has a null span.

This is **not yet** complete expression provenance through all transforms;
some specialized inference paths and transformations need further origin
propagation. A future positioned parser written in Nail could replace the
read-only Haxe sidecar. The current implementation remains opt-in and is
exercised on Haxe, Node and PHP.

## Dogfooding: hygienic macro expander written in Nail

The **opt-in experimental** `nailMacroExpandSyntax` function implements the
core of local hygienic macro expansion entirely in Nail (near the end of
`stdlib.nail`). It accepts and returns `Program` Syntax:

```nail
nailMacroExpandSyntax ( parseSource source )
```

The transformation handles local `macro name params = quote ( expression )`
declarations; `expand` invocation spines, positional `unquote` substitution,
overapplied macro results, lexical macro scope and self-reference,
source-scope caller arguments, and hygienic `Lambda` binding renaming.
Templates resolve free identifiers to reserved `#macro_global_` names;
binders introduced in templates receive reserved `#macro_local_` names.
The names are deterministic from their structural expansion paths, not from
a mutable global serial, and nested invocations use distinct paths.

Error cases (duplicate macro names/parameters, unknown macro or unquote
parameter, malformed quote and nested quote) return `MacroError` Syntax.
Recursive expansion has a depth limit.

### Module-aware Nail macro expansion (opt-in)

`nailMacroExpandWithModules` accepts `NMRequest(Program, NMModules)`, where
`NMModules` holds `TCBinding(moduleName, Program)` entries. The expansion
logic is **written in Nail**: module scope, selective imports and exports,
transitive dependency traversal, lexical capture of imported definitions,
re-export restrictions, duplicate checking and circular import detection.
Definitions retain the environment in which they were declared; imports
do not inherit the caller's variables.

The Nail transformer now builds a **persistent module-export cache**:
`nmPrepareModules` traverses the import graph, resolves each module's
exports at most once, and stores the result under its logical module key.
Cyclic imports and re-export restrictions still fail rather than creating
partial export tables. The resolver itself remains source-text-only; the
cache is ordinary Nail `Syntax` with no mutable host map.

Expansion work is also **bounded in Nail**. An internal `NMExpansionStep`
record carries the transformed `Syntax` and a numeric *remaining fuel*.
Every recursive expression visit and top-level form consumes fuel, with
the remainder threaded through sibling subexpressions, caller arguments
and nested calls. A conservative upfront charge also accounts for the
number of core Syntax nodes in the caller and every parsed module. The
default cap is **25,000 units** (independent of the VM's instruction limit).
Exhaustion returns `MacroError("macro expansion work limit exceeded")`.
The pure Nail functions `nailMacroExpandSyntaxBudgeted(program, fuel)`
and `nailMacroExpandWithModulesBudgeted(request, fuel)` allow experiments
with a smaller or larger cap; the existing public names use the default.
The special tiny-budget entry points are available for deterministic tests.

The budget measures source Syntax size and expansion traversal visits,
not wall-clock time or a physical byte allocation. The VM continues to
provide an independent interpreter step limit for other execution costs.

`NailMacroModuleInputs.collect` is a narrow Haxe adapter. It asks a
caller-provided resolver for source text **once per logical module**, parses
the returned source using Nail's `parseSource` and `modernRewrite`, and
collects transitive import keys by reading Nail's Syntax. It does **not**
invoke the Haxe parser, macro expander, or typechecker. It checks module
dialect compatibility and bounds module discovery to 256 entries.

Use `NailSourceAnalysis.analyzeNailMacros(source, boot, resolver, sourceId)`
to opt into this path, or call `tcCheckSourceNailModulesTraced` with the
corresponding prepared `NMSourceRequest` Syntax directly. Diagnostic
origin mapping is **different in the Nail-only opt-in path**: Nail's
`nmFaultMacroOrigin` uses the traced type-checker failure, the original
parsed Syntax, and imported macro definitions' lexical scopes to resolve
which module and macro own an unambiguous unknown identifier. Its result
is an immutable symbolic `NMOrigin` (defining source, macro and name).
The host only uses `SourcePositions.scan` to map that identity to the
original source token span; it does **not replay the Haxe macro expander**.
An argument inserted through `unquote` retains its caller location.

### Per-node provenance, captured during Nail macro expansion

The `NMExpansionStep` record additionally carries a parallel `trace`
tree. Every generated `Apply`, `Lambda`, `If`, variable and literal
has an `NMTrace` pointing to its origin:
`NMSource(definingModule, macroName, structuralChildPath, callSitePath)`.
The fourth field is the structural path to the **outermost original source
invocation**, propagated through nested, imported and recursively expanded
macro templates. Caller-owned `unquote` arguments keep their own origin.
Arguments that pass through `unquote` retain **their caller-owned trace**
rather than inheriting the macro template's trace. The shape of the
ordinary `Program` and its five core expression constructors remains
unchanged.

`nailMacroExpandWithModulesTraced(request)` performs **one** expansion
and returns `NMExpansionTraced(Program, NMTraceProgram)`. Its ordinary
untraced sibling discards the sidecar and returns the same `Program`.
On errors, the Nail function `nmFaultNodeOrigin` combines the HM
checker's traced form ordinal and expression-child path with this sidecar
to select the **actual failing generated node**, not a matching source
name or an unrelated macro invocation.

`NailSourceAnalysis.analyzeNailMacros` converts the symbolic node origin
into source coordinates by scanning only the owning macro declaration.
Numeric infix operators and source-authored `if` expressions are
disambiguated by Nail's own ordered structural token paths, including
repeated occurrences of the same symbol. **`nmSourceOperatorTokens`**
uses infix traversal and excludes synthetic pattern-lowering conditionals.
Straightforward function applications and lowered `match` sites are
also supported. Repeated `match` keywords
inside one macro template are disambiguated by their corresponding
Nail-parsed lowered binders, preserving the checker-node path and the
original source order. A mismatch between the lowered AST and source
keyword count fails closed instead of guessing an origin.
The same mapping recognizes generated `function | ...` expressions,
which lower internally to a match but point back to the `function` token.
For branch-specific errors (unknown/mixed sum constructors, duplicate
branches, or incorrect binding arity), the Nail checker carries the
specific failing constructor predicate path. **Nail functions
`nmSourcePatternTokens` and `nmSourceConstructorTokens`** now recover
the ordered, path-labeled `match`, `function`, and constructor tokens
from the Nail-lowered Syntax, including patterns nested in scrutinees and
branches. Haxe no longer reimplements pattern, numeric or conditional AST
traversals. The Nail-written `nmSourceTokenHintAtPath` also selects the
exact template node and derives its surface-token hint, distinguishing
missing structural paths from selected nodes with no lexical token.
The Nail-written `nmSourceTemplateInOwner` also looks up the defining
module and macro declaration, reusing `tcFind` and `nmParameters` rather
than a Haxe declaration/quote AST walk. Missing and duplicate declarations
fail closed. `nmSourceDiagnosticProjection` now owns the fault-dependent
choice between a pattern keyword, offending constructor, numeric operator
or unique source-token fallback. Haxe no longer maintains separate copies
of checker diagnostic message prefixes or walks the token maps to select
a matching AST path. It scans the original source, validates complete
token-count agreement and projects Nail-provided tokens to UTF-16 spans.
Coverage errors remain attached to the enclosing `match`/`function`.
Ambiguous token order fails closed. No Haxe macro replay occurs
on this opt-in path. The preceding `nmFaultMacroOrigin` lookup remains
as a compatibility fallback for unknown-name errors whose new projection
cannot yet find an exact original token.

**VM boundary measurement:** `nmSourceOwnerDiagnosticProjection` composes
`nmSourceTemplateInOwner` and `nmSourceDiagnosticProjection` inside
Nail, returning only the symbolic token policy to Haxe. Template
lookup + fault-token selection now require **one** host-to-Nail VM call
per traced origin instead of **two** (and the complete path falls from
four Nail invocations to three: fault origin, caller lookup, combined
template/policy). A non-gating microbenchmark runs on Haxe, Node, and
PHP in the typechecker probe: eight warm-ups per implementation, then
five alternating-order batches of 64 calls per implementation. It
reports the median and raw samples, without imposing a CI timing
threshold. Six parity fixtures cover local/imported macros, invalid
paths, missing modules, duplicate declarations, and distinct fault
classes. No bytecode or executable-Syntax format changes.

The first CI measurement (run 44508506674, 19 Nov 2026) used only
**one batch of 32 cases** per implementation:

| Runtime | Two VM calls per case | One fused VM call per case |
| --- | ---: | ---: |
| Haxe interpreter | 145.37 ms | 150.61 ms |
| Node/JavaScript | 10.62 ms | 9.11 ms |
| PHP | 100.53 ms | 103.33 ms |

These results demonstrate fewer host/VM boundary crossings, **not** a
uniform wall-clock improvement. Small samples, VM execution costs, CI
load, JIT effects, and run order can mask or outweigh the avoided call.
Do not describe this refactoring as a general performance speedup
without repeated, comparable measurements.

**End-to-end diagnostic profile:** the optional `phaseObserver` on
`NailSourceAnalysis.analyzeNailMacros` records elapsed milliseconds for
source preparation, module discovery, traced expansion, HM checking,
result decoding, and source-coordinate diagnostics. The typechecker
probe runs five cases with a shared, already-initialized `BootRuntime`,
reports medians and total-run samples, and verifies that the complete
diagnostic report is identical with and without observation. Timings
include per-phase host/VM interaction where relevant, but exclude
creating the shared runtime. This isolates likely costs more meaningfully
than the microbenchmark of one provenance helper. The observer is opt-in;
ordinary analysis has no additional clock reads.

**v0.55 consolidation matrix (experimental):** four workloads share the
same generated numeric type error, but vary caller size (one macro versus
16 extra definitions) and imported module size (one exported macro
versus 24 additional private macro declarations). Each workload runs
five profiled cases with a shared runtime, plus an unprofiled baseline.
Tests verify both source and template spans, exact equality of the
profiled/unprofiled reports, and presence of every timing phase. The
matrix logs per-phase medians and five raw total times on Haxe, Node
and PHP; measurements remain non-gating and are *not* a broad
compiler-performance claim.

The Haxe module-discovery adapter now decodes the **importing unit's**
language version and numeric dialect lazily, once per collection, rather
than rescanning the same caller source for every imported module. This
preserves all module compatibility checks, including transitive imports.
A diamond-dependency test verifies each imported source is fetched once,
with the same module table as before. No cross-request cache or changed
macro semantics is introduced.

**Parsing versus rewriting (v0.55):** each imported module goes
through the existing `parseSource` and `modernRewrite` Nail functions.
A non-gating five-sample stage probe measures these independently for a
small module and a module with 24 private macro declarations. Every
stage result must match the output of the ordinary
`NailMacroModuleInputs.parsedModern` path exactly (up to generated
binder renaming). The probe identifies whether parsing or the numeric
AST walk dominates before changing compiler semantics or the VM.

**Caller-site disambiguation:** the Nail trace carries the original
invocation's **structural call path**. Nail-written
`nmSourceCallsInForm` selects the requested original source form by
checker form ordinal, omitting private macro/import/export declaration
markers. Then `nmSourceCallTokens` traverses that form's unexpanded
expression, returning ordered `NMTokenOrigin(path,macroName)` records.
Haxe no longer implements either the source-form AST selection or the
`#macro_expand` application spine: it compares this list with original
scanned `expand name` pairs and maps matches to source offsets.
Disagreement, unsupported forms and out-of-range ordinals fail closed,
using only prior unambiguous fallbacks. Repeated names, nested arguments
and imported invocations remain supported. No runtime AST or bytecode
change occurs.

**Conservative limits:** unsupported lowerings, source/AST call-count
mismatches, duplicated symbolic template tokens, and absent exact source
positions leave the relevant span unset. We never fabricate locations.

The default `analyze` path still uses its existing optional Haxe
macro-provenance replay, and neither `analyze` nor the production compiler
switches expansion strategies.

The tests compare the Nail-expanded program with the Haxe oracle up to
bound-variable alpha-equivalence, including transitive imports, lexical
capture, typed contextual DSLs, imported macro validity and rejection of
non-exported/re-exported names and import cycles.

The `tcCheckSourceNailMacrosTraced` experiment runs the entire **local**
source checking pipeline through Nail's typed parser, normalized numeric
Syntax, Nail's macro expander, typed metadata restoration, and Nail's HM
checker. It does not invoke the Haxe expander or typechecker:

```haxe
var checked = boot.invoke("tcCheckSourceNailMacrosTraced",
  nail.Value.Text("nail 0.54 ; macro id x = quote ( unquote x ) ; expand id 1 ;"));
```

The test suite `NailTypecheckerProbeTestMain` checks the resulting Syntax
against the Haxe macro oracle **up to alpha-equivalence**. It normalizes
only bound variable names: free global names remain exact, so unintended
variable capture or wrong lexical resolution fails the comparison. Tests
also check Nail's type verdict independently on both expanded programs,
and validate rejection of malformed macro declarations and calls.

**Known gaps before substitution in the public compiler:** full
equivalence of error messages and fully precise **source-token projection**
for every supported expression lowering. The Nail macro transformer now
records each output node's structural source path and the checker can
select the exact faulty node; imported/local numeric and conditional
failures and unambiguous pattern sites can be mapped to original tokens.
Repeated calls to the **same** macro within one expression, complex
match lowerings and arbitrary AST/source transformations still require
safer projection rules. Measured throughput on large recursive templates,
allocation/byte budgets beyond the work limit, and differential parity over
the full macro corpus also remain open. The existing production compiler
remains authoritative.

## Parity and coverage gaps

The Haxe checker is used **only in differential tests**, not by the Nail
inferencer. See `src/NailTypecheckerProbeTestMain.hx`.

The following are not yet complete:

- Higher-order and partially applied overloaded numerical relations,
  nonconcrete numeric operand inference and explicit `Eq` syntax in
  user-authored signatures (inferred qualified schemes are implemented)
- Full source-pattern provenance/locations and richer pattern syntax;
  ordinary and hygienically macro-renamed sum subjects are recognized,
  including constructor ownership, binding arity and exhaustiveness.
  Generic recursion edges remain deferred
- Complete structural row algebra: open-row **reordering**, row-lacks
  constraints and row-polymorphic ABI
- Generic/recursive structural aliases, applied nominal or `Node` types
  not yet available to the experimental checker
- Full standard-library primitive signatures and typed module signatures;
  source positions for imported macro templates are tracked by logical
  module name, and caller-side typed metadata now survives expansion, while
  hygienic macro rewriting itself is still a host syntax primitive
- Generated expression ancestry through macro expansion and specialized
  numeric/equality inference paths; no invented spans for unresolved origins
  or arbitrary type mismatches
- Performance and bounded-resource policies for adversarial/large terms

Unsupported cases must return a diagnostic rather than being accepted with
invented types. **The Haxe checker remains authoritative for public code.**

## Reproduce

From the root of the repository, with Haxe 4.3.x, Node and PHP installed:

```sh
haxe seed-image.hxml
haxe nail-typechecker-test-interp.hxml
haxe nail-typechecker-test-js.hxml
node build/tests/nail-typechecker.js
haxe nail-typechecker-test-php.hxml
php build/tests/php-nail-typechecker/index.php
```

The test suite includes successes and failures and compares outcomes with
the independent Haxe checker (using its explicit open-row opt-in when
relevant). It also validates that the Nail checker runs from its bytecode
image on Haxe, JavaScript and PHP.
