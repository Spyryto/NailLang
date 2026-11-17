# Contextual DSL blocks — parser/type-checker experiment

**Status: exploratory. Not a Nail language feature, version or public ABI.**
The ordinary Parser constructor, supported 0.54 syntax, self-hosted source
compiler, module loader and VM remain unchanged. Do not ship the experimental
constructor as a source-language guarantee.

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
This bridge does not infer interfaces from unknown function parameters or
automatically integrate context discovery into the complete source compiler.

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
4. Every field of the supplied interface is projected eagerly in this
   prototype. A production design could instead lower **referenced**
   fields. Thus validation currently rejects missing fields even if the
   body does not use them.
5. Positions of generated projections and lexical binders are not yet
   source-provenance mapped. This must be solved before production diagnostics.
6. Unlike public module imports (0.54), the experimental record interface
   is provided by the embedding test, not resolved from compiled modules.
7. Because the ordinary parser remains untouched, original surface source
   containing contextual blocks cannot yet be compiled by the **Nail
   source-free compiler**. The compiled lowered AST is an independent
   demonstration, not parity for the original source.

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

**Decision still open:** use `Html { ... }`, an explicit `with Html { ... }`,
a distinct punctuation form, or an alternative. Do not merge the draft PR
as a shipped feature before discussing the inference model and syntax.
