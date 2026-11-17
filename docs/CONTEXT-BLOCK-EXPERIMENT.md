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
constructions remain unchanged. The explicit context map supplies the
list of imported field names and is intentionally
**not** inferred from an arbitrary record value in this experiment.

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

The same AST works in the existing Haxe bytecode compiler and VM, and the
existing type checker verifies closed structural records of functions.

## Boundaries deliberately explored

1. A record **passed as a function parameter** works at runtime, because the
   lowering accesses ordinary fields. However, the current HM checker cannot
   infer an unknown record parameter's fields (`TVariable` projection
   currently requires a unique nominal accessor). Full static typing of
   generic context parameters requires **open rows / row polymorphism**
   or explicit type evidence/annotations.
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
values versus currently impossible static inference, malformed context
interfaces and unclosed blocks.

**Decision still open:** use `Html { ... }`, an explicit `with Html { ... }`,
a distinct punctuation form, or an alternative. Do not merge the draft PR
as a shipped feature before discussing the inference model and syntax.
