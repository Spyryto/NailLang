# NailSeed v0.29 — opt-in exact numeric compiler/runtime integration

An independent compiler and runtime snapshot derived from the stable v0.27
language and the v0.29 compact-number lab, in `v0.29-runtime/`.

## Intended verified slice

- Existing unmarked Nail programs use unchanged floating `Number` values,
  `TNumber` inference, native arithmetic and v1 bootstrap images.
- First nonempty line `# nail: 0.29` opts the current **whole source file**
  into exact numeric literals. They are `ExactNumber(FastValue)` at runtime
  and `TExact` in the type checker.
- Arithmetic `+ - * /` and order operators use exact primitives (via a
  checked rewrite), not implicit Float promotion. Equality is polymorphic
  but rejects mixed exact/legacy runtime numbers.
- The Haxe parser and the Nail-written parser/transformer independently
  produce the same five-constructor expression AST / Syntax representation,
  with a canonical `ExactNumber E:n/d` leaf in bytecode. Both AST and
  structured bytecode VMs execute the same immutable values.
- The source-free bootstrap compiler chooses the versioned exact path
  without calling the host parser.
- `ExactImage` uses a separate v2-exact JSON envelope, retaining explicit
  decimal-string rational payloads; legacy v1 decoders reject its header.
- Cross-target comparison tests cover Haxe, JavaScript and PHP and are run
  before the complete inherited bootstrap regression and fixed-point suite.

## Deliberate boundaries

This is an **opt-in compiler/runtime integration candidate**, not a change
to all existing Nail programs. User-facing explicit exact-to-Float
conversions, mixed-dialect module linking, general numeric type classes,
production memory budgets, and complete integration with numeric collection
indices and generated declarations still need design and tests.

See [../v0.29](../v0.29/) for numerical performance work and the
repository ROADMAP.md for the v0.40 feature balance.
