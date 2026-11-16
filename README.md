# NailSeed v0.30 — Typed procedural transformers written in Nail

v0.30 adds a **public, opt-in transformer API** to the independent v0.29-runtime
snapshot. Existing expression-template macros, exact-number dialect support,
the five-form expression core and the source-free compiler remain intact.

A procedural transformer is an ordinary pure Nail function:

```nail
def emit program =
  if syntaxTag program == " Program " then
    syntaxNode " Program " [ ...new definition Syntax nodes... ]
  else syntaxNode " Program " [] ;
```

Its required inferred signature is `Syntax -> Syntax`. Unlike the existing
`macro name ... = quote (...)` syntax, it may **compute Syntax dynamically**
using Nail functions, recursion, conditions and the existing immutable
`SyntaxLeaf`/`SyntaxNode` APIs. No new interpreter opcode, object model,
fexpr, or privileged compilation primitive is introduced.

## Example

See [examples/procedural-plus-ten.nail](examples/procedural-plus-ten.nail).
The Nail function `emitPlusTen` generates a `plusTen` declaration with a
fresh local variable, and returns a `Program` containing only that definition.

A second example, [examples/procedural-identity.nail](examples/procedural-identity.nail),
shows that the generator can use the ordinary **Nail standard library's**
`syntaxDefine`, `syntaxLambda` and `syntaxVar` helpers. The host contract
checker reads the bundled stdlib's inferred signatures once and reuses an
isolated copy for each transformer. In a minimal custom host build without
that resource, transformers may still use the core Syntax primitives, but
stdlib-only helper names must be provided by the host.

Host integration (Haxe, with the same API on JS and PHP):

```haxe
var original = SyntaxEncoder.program(
  new Parser('def base = 32 ;').parse());
var transformerSource = /* contents of procedural-plus-ten.nail */;
var contracts = [{
  name: 'plusTen', type: TFunction(TNumber, TNumber)
}];

var emitted = ProceduralTransformer.generateHost(
  original, transformerSource, 'emitPlusTen', contracts);

// Or run the *same Nail transformer* with the source-free bootstrap:
var fromBootstrap = ProceduralTransformer.generateBoot(
  original, transformerSource, 'emitPlusTen', contracts);

var bytecode = ProceduralTransformer.compile(original, emitted, contracts);
// bytecode contains both def base and def plusTen; plusTen base evaluates to 42
```

### Contract and hygiene

- The caller supplies a validated source `Syntax.Program`, transformer source,
  transformer entry name and an **explicit closed monomorphic signature** for
  each emitted definition. No unchecked generated declarations can enter
  `ProceduralTransformer.compile`.
- The generated result must be another `Syntax.Program` of **fresh definitions
  only**; unexpected forms, duplicate names, wrong result types and unknown
  references are errors. The original Program is never mutated.
- A generated lambda must bind `#proc_local_<name>`, referring to that binder
  using the same private marker. The hygiene pass deterministically rewrites
  every marker to a fresh `#proc_gensym_<id>_<name>`, preserving caller free
  variables. Bare `x` binders, dangling markers and fabricated/duplicate
  private IDs are rejected.
- The public compile boundary verifies already-prepared IDs again, and checks
  types again, so directly supplying arbitrary Syntax cannot bypass it.
- Type-contract errors can include an optional source call-site span. Complete
  nested source-origin maps for arbitrary procedural transformations are not
  yet implemented.
- The transformer runs as an ordinary Nail closure, under the existing
  evaluator instruction budget, with **no I/O or privileged callbacks**.

## Test and runtime compatibility

```sh
# In v0.30/, after generating the bootstrap image:
haxe seed-image.hxml
haxe procedural-transformer-test-interp.hxml
haxe procedural-transformer-test-js.hxml && node build/tests/procedural-transformer.js
haxe procedural-transformer-test-php.hxml &&
  php build/tests/php-procedural-transformer/index.php
```

GitHub Actions additionally runs the inherited v0.29-runtime regression,
type inference, expression macro, module macro, exact-number, fixed-point
bootstrap, stress and distribution checks on Haxe, Node and PHP. The new
tests compare the Haxe AST VM, the Nail-written reference compiler and the
source-free compiled Nail compiler, plus malformed/unsafe outputs.

## Deliberate limits

This is **Nail-authored procedural declaration generation through a public
host API**, not user-defined `macro` registrations directly in the Nail
source grammar. It does not yet support arbitrary program rewrites, automatic
type inference of promised polymorphic declarations, phase-specific I/O,
mixed-version module linking or complete inferred hygiene for unmarked syntax
splices. Procedural transformers must explicitly mark the bindings they
introduce. These boundaries make the first reusable API predictable and
testable without expanding the trusted runtime core.

See [SPEC.md](SPEC.md), the previous [v0.29-runtime](../v0.29-runtime/) and
the repository's [roadmap](../ROADMAP.md).
