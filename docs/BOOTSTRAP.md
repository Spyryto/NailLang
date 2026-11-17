# NailLang bootstrap stages

The runtime uses **Haxe for VM primitives**, but the *source-free* compiler
distributions do **not** ship the Haxe source parser or reference compiler.
Haxe remains the trusted **stage-zero seed** and an independent test oracle.

## Three stages, one canonical bytecode image

```text
                      Nail stdlib.nail
                            |
             +--------------+--------------+
             |                             |
      STAGE 0: Haxe                    STAGE 1: Nail
   Parser + BytecodeCompiler     BootRuntime(seed image)
             |                             |
      stdlib-image.json --------------> self-image.json
                                           |
                                    STAGE 2: Nail
                                  BootRuntime(stage 1)
                                           |
                                    same bytecode tape
```

1. **Stage 0**: `haxe seed-image.hxml` invokes the build-only
   `tools/bootstrap/BootstrapImageMain.hx`. The independent Haxe parser and
   compiler translate the current `stdlib.nail` into
   `build/bootstrap/stdlib-image.json`, with an explicit image format and
   language-version tag. The result is decoded and re-encoded, and must be
   byte-for-byte deterministic. There is no dependency on the AST execution VM
   in this build entry point.
2. **Stage 1**: `haxe rebootstrap-node.hxml`, followed by
   `node build/tests/rebootstrap-node.js`, compiles the **same** source using
   Nail functions running on the source-free VM loaded from the seed image.
   This writes `build/bootstrap/self-image.json` only if stage-zero and
   stage-one ordered postfix records agree.
3. **Stage 2**: The rebootstrap driver loads the stage-one image and recompiles
   the source *again* using Nail. Stages one and two must also produce the
   identical tape. The comparison is part of `nail.Rebootstrap.verify`.

The optional `haxe rebootstrap-image.hxml` runs stages one and two on the
Haxe interpreter without Node. The images, not a hidden runtime parser,
bootstrap the distributed compiler.

## Packaging boundary

`haxe boot-js.hxml` and `haxe boot-php.hxml` embed the verified
`self-image.json`, and compile with `-D nail_seed_only` and Haxe dead-code
elimination. They expose `BootRuntime` over `ByteVm`; parsing, macro
expansion and compilation of user Nail source are implemented by the
**precompiled Nail standard library**. The common VM, bytecode decoding,
numeric primitives and necessary Syntax adapters remain implemented in Haxe.
Both evaluators now use `RuntimePrimitives.environment()` and
`RuntimePrimitives.apply()`, so the source-free `ByteVm` no longer depends
on the AST evaluator even for primitive dispatch. `RuntimeValues` owns
JSON-friendly value presentation for both runtimes. The bundle guard checks
for `Vm` as well as the compiler, parser and type checker: the source-free
distribution must **not** include the Haxe AST VM at all.

`node tools/check-boot-boundary.mjs` inspects **both generated artifacts**:
neither may include Haxe `Parser`, `BytecodeCompiler`,
`RecordLowering`, `SumLowering`, or `TypeChecker`. It fails CI/release
builds on leakage. This is a packaging regression check, not proof of
cryptographic trust or of a minimal runtime dependency graph.

The **full** distributions, built with `js.hxml` and `php.hxml`, remain
separate. They intentionally expose the Haxe parser/type checker/reference
compiler for development and diagnostics. `src/nail/BytecodeCompiler.hx`,
`src/nail/Parser.hx` and the Haxe lowerers stay available for stage zero and
differential testing; they have **not** been removed or rewritten in Nail.

## Reproduce the boundary check locally

Install Haxe 4.3.7 and Node 22 (PHP is needed to execute PHP tests), then:

```sh
haxe seed-image.hxml
haxe rebootstrap-node.hxml
node build/tests/rebootstrap-node.js
haxe boot-js.hxml
haxe boot-php.hxml
node tools/check-boot-boundary.mjs
```

CI runs those stages, differential compiler/typing suites, stage fixed-point
checks, the source-free CLI smoke tests, and bundled JS/PHP runtime checks.

## Constraints and future opportunities

- The Haxe **reference compiler must remain independent** while Nail is
  pre-1.0. Removing it from the seed would require a separately pinned,
  auditable prior bootstrap image and a different chain-of-trust policy.
- The runtime still shares Haxe's `Vm` primitive implementation and
  `SyntaxBridge`; it is **not** a pure Nail runtime. The source parser and
  type checker are deliberately absent from source-free distributions.
- The stage-zero **entry points** are under `tools/bootstrap/`; the shared
  seed compiler and runtime primitives stay under `src/nail/` so both
  the full developer target and bootstrap tests can reuse them.
- Runtime primitives live in `RuntimePrimitives` (still implemented in Haxe).
  Nail remains dependent on a portable low-level VM and finite native boundary.
  Track source-free bundle size before claiming a performance or packaging gain.
- A future experiment may split primitive families (numeric, Syntax, vectors)
  only if it measurably improves cohesion; avoid unnecessary indirection.

## Code size and runtime boundary measurement (2026-11-17)

The AST evaluator was successfully separated from the source-free runtime
**without duplicating primitive semantics**. Both evaluators use the same
`RuntimePrimitives` entry points. `RuntimeValues` holds presentation only;
the bytecode runtime and boot wrapper do not reference `Vm`.

Production-file character counts relative to the pre-refactor branch:

| Component | Before | After |
| --- | ---: | ---: |
| `Vm.hx` | 29,375 | 11,462 |
| `ByteVm.hx` | 12,008 | 12,047 |
| `BootRuntime.hx` | 2,535 | 2,546 |
| New `RuntimePrimitives.hx` | 0 | 16,857 |
| New `RuntimeValues.hx` | 0 | 1,622 |
| **Total** | **43,918** | **44,534** |

The production sources **increase by 616 characters** (excluding docs and
tests). This is a separation of responsibilities and dead-code-elimination
opportunity, **not** a claim of fewer total source lines, a smaller compiled
artifact or faster execution. The CI packaging guard now rejects the AST VM
class in addition to host compiler classes in both source-free bundles.

## Macro expansion boundary (2026-11-17)

The source-free compiler uses the **Haxe** `MacroExpander` for hygienic
template expansion via the `macroExpandSyntax` native primitive. Therefore
`MacroExpander`, its AST/Syntax adapters, and the hygiene conventions are
**still functional runtime dependencies** for macro-aware compilation. A
source-free distribution means *no Haxe source parser or Haxe reference
compiler*, **not** zero Haxe compiler-time services.

Macro expansion is intentionally **once per compilation path**:

- `compileSyntax` expands arbitrary user-provided `Syntax` and then calls
  `compileExpandedSyntax`.
- `compileModernSource` and `compileExactSource` expand macros **before**
  rewriting numeric syntax, then call `compileExpandedSyntax` directly.
- Compiling imported macro modules similarly expands them with the resolver
  before rewriting, then calls the same internal entry point.

Previously the last two paths invoked `compileSyntax` on already-expanded
syntax, forcing an unnecessary second AST scan. The internal helper is an
implementation contract, **not** a new source-language feature. Future
dogfooding can replace the remaining native macro expansion only once a
full Nail implementation preserves hygiene, lexical scope, imports, work
limits, diagnostics and bootstrap fixed-point parity.
