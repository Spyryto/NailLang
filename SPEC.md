# NailSeed v0.14 — Bootstrap image specification

The **semantic core and ISA are exactly v0.13**. This release adds a deterministic build-time image format and a source-free runtime entrypoint; it does not assert full self-hosting.

## Postorder image

A JSON object with fields:

- `format`: the exact string `nailseed.postfix-image.v1`.
- `records`: an array of records, each exactly three elements.
  - `["L", tag, text]`: a `SyntaxLeaf(tag,text)`.
  - `["N", tag, arity]`: a `SyntaxNode(tag, children)` consuming the most recent `arity` complete nodes, preserving left-to-right child order.

The final record stack must contain exactly one `SyntaxNode("Bytecode",...)`. The decoder checks the format tag, row shapes, arities, stack balance and the final root. It does not trust the image to be a safe executable: normal ByteVM validation, instruction budgets and host security constraints still apply.

This is a **transport representation** for the already-existing `Syntax`-encoded structured bytecode, not a replacement ISA. It deliberately avoids a recursive JSON tree and supports an iterative loader on Haxe, JS and PHP.

## Two-stage bootstrap

**Stage 0 / build:** `BootstrapImageMain` uses the reference `nail.Parser` and `nail.BytecodeCompiler` to compile the full `stdlib.nail`, writes `build/bootstrap/stdlib-image.json`, and checks the encode/decode roundtrip.

**Stage 1 / packaged runtime:** `BootRuntime` reads the image compiled into its resources, decodes it and executes it with `ByteVm`. Thus `parseSource`, `compileSource`, `compileSyntax`, the standard library and their Nail dependencies are installed as compiled bytecode closures in one run.

**Stage 2 / user code:** `BootRuntime.compile(source)` calls the compiled **Nail** `compileSource` function, and `BootRuntime.run(source)` executes that bytecode using the same `ByteVm`. The host Haxe parser is not called for user code.

The boot-only target defines `nail_seed_only`. The old `Vm.run(source)` method then deliberately throws instead of invoking Haxe `Parser`, to ensure that the old entrypoint cannot accidentally become an implicit runtime bootstrap.

## Testing invariants

- Existing runtime, type, parser, compiler and structural tests remain in place.
- New `BootTestMain` tests source execution from only the packaged image across all three targets, errors, currying, higher-order functions, `match`, user-defined recursion and compiled bytecode roundtrips.
- Image-specific tests cover noncanonical/malformed headers, arities, roots and thousands of levels of nesting without native recursion.
- GitHub Actions creates image before compiling/running boot tests and packaging new JS/PHP boot distributions.
- Integration tests use the public Node `NailSeedBoot.create()` API and PHP CLI without first loading `stdlib.nail` or running the Haxe source parser.

## Known limits

The initial image depends on **Haxe at build time**. The Nail-written parser/compiler are still subject to the existing restricted whitespace tokenization, ASCII-related text limitations, and resource budgets. Runtime type checking is not included in the minimal boot target; it remains available in the historical full distribution. Source-to-bytecode execution is not a hardened sandbox.
