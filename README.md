# NailSeed v0.15 — Reproducible self-rebootstrap

This experiment keeps the **exact v0.14 runtime, ISA, and source language**.
It verifies that the Nail-compiled `compileSource` can regenerate the complete
standard-library bootstrap image, *including its own compiler*.

## Three-stage fixed point

1. **Stage 0 (reference)**: Haxe compiles `stdlib.nail` into `stdlib-image.json` (existing bootstrap tool).
2. **Stage 1 (Nail)**: the bytecode runtime initialized with stage 0 executes the Nail-written `compileSource` on the *entire* `stdlib.nail`, generating `self-image.json`.
3. **Stage 2 (Nail again)**: a fresh runtime loads stage 1 and regenerates the image again.

The verification compares **the ordered postfix instruction records**, not JSON
object field order. A SHA-256 fingerprint of the canonical record tape is
reported. This is a strong reproducibility test, not a proof of semantic
correctness or a compiler that can run without its seed image.

## Build and test

From `v0.15/` with Haxe 4.3.7:

```sh
haxe seed-image.hxml
haxe rebootstrap-image.hxml
haxe rebootstrap-test-interp.hxml
haxe rebootstrap-test-js.hxml && node build/tests/rebootstrap.js
haxe rebootstrap-test-php.hxml && php build/tests/php-rebootstrap/index.php
```

`rebootstrap-image.hxml` produces `build/bootstrap/self-image.json`.
The source-free JavaScript and PHP distributions and their boot tests embed
**the Nail-regenerated `self-image.json`**, not the Haxe stage-zero image.
CI also runs the inherited regression suites. The Haxe generator and JavaScript tests independently rebuild both stages.
The normal PHP test checks the exact Nail-generated image and compiles/runs
several programs from it; the **full PHP rebuild is opt-in** due to runtime
cost (`haxe rebootstrap-test-php.hxml -D full_rebootstrap` then execute PHP).

## Key design boundary

The initial Haxe-generated image remains **a trusted seed**. This is a
self-rebuilding compiler after seed bootstrap, **not** yet an independent
compiler that generates itself from nothing. `Rebootstrap.hx` uses only
`BootRuntime.compile` and the portable image encoder/decoder; it does not
invoke the host parser or reference compiler.

The previous versions are archived unchanged.
