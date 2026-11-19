# Contextual DSL blocks — parser/type-checker experiment

**Status: exploratory PR, not a released Nail language version or public ABI.**
The ordinary Haxe Parser constructor and shipped 0.54 semantics remain unchanged.
The **self-hosted Nail-written source compiler now has experimental contextual
syntax and erases structural contracts/parameter annotations**, while the
runtime AST, VM opcodes and module loader remain unchanged. This is intentionally
unmerged and not a public-language guarantee.

## Motivation

Try the same lexical scope idea for HTML, GUI, RPC, and operating on state:

```nail
def Html = { h2 = makeH2 , div = makeDiv } ;
def view title text = Html { [ h2 title , div text ] } ;
```

The contextual expression is not a macro transformer and is not automatically
a sequence of effects: it returns the value of the contained expression.

**Capitalization:** `Html { expression }` and `html { expression }`
share the same grammar. The identifiers themselves remain case-sensitive,
so they can refer to different structural values and produce different results.
Uppercase remains meaningful for nominal type declarations and constructors,
not for contextual block recognition. A value named `Html` does not become
a DSL merely because it is capitalized.

## What is implemented

An **opt-in parser proof**:

```haxe
var contexts = new haxe.ds.StringMap<Array<String>>();
contexts.set("Html", ["h2", "div"]); // verified interface supplied by caller
var forms = new nail.Parser(source, contexts).parse();
```

The parser distinguishes `Person { name = value }` from
`Html { expression }` by the immediate tokens `name =`, not by type
inference. Existing lowercase function application to an anonymous record
(`render { name = value }`) is likewise preserved. Other legacy record
constructions remain unchanged. The context field map can now be **derived
from an already checked, closed structural value interface** with
`ContextInterfaces.fromChecked(checker, ["Html", "html"])`.
This Haxe-side bridge does not infer interfaces from unknown parameters.
The Nail-written source compiler separately resolves contextual fields from
explicit parameter or value annotations and preceding structural type aliases.
That path requires named structural contracts; automatic discovery for
unannotated receivers remains deferred.

The block is lowered immediately to the existing five-expression AST core:

```nail
Html { [ h2 title , div text ] }

# approximately
let ctx = Html in
let h2 = ctx . h2 in
let div = ctx . div in
[ h2 title , div text ]
```

Actual lowering uses an internal, non-source-spellable temporary. The
context is evaluated once. Nested blocks obey ordinary lexical shadowing;
local bindings *inside* the block supersede context bindings; context fields
supersede globals/outer parameters. No hidden member calls or name lookup
at runtime is added.

The same AST works in the existing Haxe bytecode compiler and VM. An opt-in
checker experiment (activated by the parser's explicit context-probe mode)
also infers **open structural rows** for unknown record parameters:

```nail
def getH2 renderer title = renderer . h2 title ;
# Inferred: renderer must supply h2, but may contain other fields.
```

This is not a nominal interface, needs no `implements` declaration, and
introduces **no new runtime value or bytecode opcode**. The inference
representation `TOpenStructural(fields,rest)` is normalized, generalized
and unified with concrete closed rows. The existing source-language 0.54
checker intentionally retains its current behavior outside this opt-in probe.
Public module scheme serialization explicitly rejects experimental open rows
until an auditable stable ABI exists.

## Confirmed syntax: optional structural contracts

The following **experimental** syntax is accepted by the opted-in parser
and checked before compiling the erased core forms:

```nail
type Html = {
  h2 : Text Text ,
  div : Text Text
} ;

def render ( html : Html ) title =
  html {
    h2 title
  } ;
```

Here the first parameter has an explicit, structural minimum contract.
The second parameter still receives its type by inference. Primitive
annotations are also supported:
`def render ( html : Html ) ( title : Text ) = ... ;`.
A declared value can use `def html : Html = ... ;`.

These contracts are compile-time only and use the same lexical record
field resolution as the earlier context experiment. Inferred open
rows remain the mechanism that allows a value to contain additional
fields. Type aliases are **not** nominal record declarations. Existing
relations such as `def divide x y : Div = ... ;` continue to use
the separate trailing function-constraint position.

Current limitations: simple primitive or previously introduced alias
types in these declarations only; no recursive/generic aliases,
no function types with arbitrary nested grouping, and no automatic
inference of context field candidates for unannotated receivers in the
source-free compiler. **The Nail-written parser now recognizes and lowers
these aliases, annotations and nested context blocks**; it does *not*
reimplement static structural contract checking. Haxe `TypeChecker.checkParsed`
verifies the contracts; source-free compilation erases them and is not
a replacement for build-time type checking. Parser annotations are sidecar
metadata, so Syntax roundtrips that discard them do not preserve their
static contract. This remains a draft language design, not published Nail syntax.


## Nail-written source compiler parity (experimental)

The same static source is now processed by **both** the opt-in Haxe frontend
and the self-hosted `parseSource` / `compileModernSource` frontend:

```nail
nail 0.54 ;
type Html = { h2 : Text Text , div : Text Text } ;
def render ( html : Html ) title = html { h2 title } ;
```

The Nail parser stores `TypeAliasDecl` / `AnnotatedDefine` as **temporary
Syntax** during lexical resolution, then erases them. An internal
`Context` Syntax marker is similarly resolved into `Lambda`, `Apply`
and `#recordGet` expressions. The core AST, bytecode and VM stay unchanged.

Resolver rules are ordered lexically: locally introduced lambdas (including
`let`) beat context fields from earlier scopes; inner contexts beat outer
contexts; missing inner members fall through to outer contexts; explicit
`html . div` remains qualified. Quoted text containing `{` is not mistaken
for punctuation. Concrete annotated values can open a context in subsequent
source forms. Untyped receivers without a known contract are rejected by
the self-hosted resolver rather than treated as an implicitly open record.

The source-free path is **not itself a static type checker**. Compatibility
of function and value annotations is checked by the opt-in Haxe type checker;
a future compiler release must integrate authoritative static validation
into the end-to-end distribution and source diagnostic pipeline.

## Correctness gate for the stacked type checker (PR #28)

The Nail-written HM checker, now integrated into this experimental branch,
has a differential regression suite against the Haxe checker for nested
contextual DSL blocks. It checks that an inner `div` with an incompatible
signature **still shadows** an outer, compatible `div` (a rejected
program, not implicit fallthrough), while explicit `html . div` selects
the outer field. Positive tests cover correctly typed inner calls and
lexical `let` shadowing; negative tests reject structurally incomplete or
wrongly typed annotated values. All run through the shared Haxe/Node/PHP
CI probe. These checks validate the experimental subset, not every
possible row-polymorphism or source-provenance case.

The existing self-hosted `BootRuntime.run` path still erases
annotations, so it must not be mistaken for static verification.
The new **opt-in** `BootRuntime.runTypecheckedExperimental(source)`
runs a Nail-written checker/compiler function that checks and compiles
the *same expanded Syntax tree*, refusing invalid annotations before
executing any application bytecode. This is limited to the
experimentally supported versioned-source subset; it does not replace
the public compile boundary or support imported source modules.
Before making this grammar authoritative for public compilation,
close the remaining type-inference/diagnostic gaps and decide how the
validated path is integrated. PR #28 remains draft until those correctness
gates are met.

## Boundaries deliberately explored

1. A record **passed as a function parameter** now works with both
   the runtime and the opt-in open-row checker. A single `h2` requirement
   may be satisfied by different records that contain additional fields.
   This is only an experimental inference feature; public row schemes,
   row-tail lacks constraints, and cross-module ABI are not finished.
   General contextual block parsing still requires a known name-to-field
   interface supplied by the experimental caller; inference of **which
   unresolved names belong to the context** is a distinct compiler concern.
2. `Person { field = value }` is a nominal record constructor and
   `render { field = value }` is ordinary application to an anonymous
   record, **not** a context expression. Future assignment syntax or
   abbreviated fields would need a separate decision.
3. The prototype accepts one named receiver, not arbitrary expressions like
   `( chooseRenderer target ) { ... }`. This keeps the parser's experiment
   bounded while demonstrating that the *lowered core* only needs a single
   receiver evaluation.
4. The prototype now projects only **free field references**
   actually used by the contextual expression. An unused interface field
   does not become a type requirement; local lambdas, `let` bindings
   and nested contexts correctly shadow corresponding names. This
   remains lexically resolved against the externally supplied candidate
   field set; automatic discovery for an unknown parameter's context is
   still a distinct design problem.
5. Positions of generated projections and lexical binders are not yet
   source-provenance mapped. This must be solved before production diagnostics.
6. Unlike public module imports (0.54), the experimental record interface
   is provided by the embedding test, not resolved from compiled modules.
7. The experimental self-hosted source compiler **now parses annotated
   contextual source directly**, desugars lexical fields into `#recordGet`
   and compiles it on Haxe, Node and PHP. Its static verification is
   presently limited to syntactic annotation/alias recognition; the Haxe
   checker is still authoritative for type compatibility, and full
   self-hosted type inference/diagnostic provenance is not implemented.

## Reproducible regressions

```sh
haxe seed-image.hxml
haxe context-block-probe-test-interp.hxml
haxe context-block-probe-test-js.hxml
node build/tests/context-block-probe.js
haxe context-block-probe-test-php.hxml
php build/tests/php-context-block-probe/index.php
```

Tests cover: source grammar disambiguation, nominal/anonymous record
construction inside the block, nested contexts and field collisions,
local shadowing, hygienic macro expansion, successful runtime parameter
values with open-row static inference, rejection of absent or mistyped
required fields, malformed context interfaces and unclosed blocks.

**Confirmed design:** `html { expression }`, with inner context field
shadowing, access to outer members via `html . div`, optional
`( html : Html )` parameter annotations and structural type aliases.
Remaining decisions concern full type-ABI support, inference of unknown
context member sets, source spans and formalized compiler parity. Do not
merge this draft PR as a shipped feature before resolving those gaps.
