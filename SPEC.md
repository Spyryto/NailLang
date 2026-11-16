# NailSeed v0.15 — Bootstrap image reproducibility

## Scope

No new syntax, opcodes or primitives; the entire v0.14 runtime is retained.

The `stdlib.nail` source includes the tokenizer, parser and compiler written
in Nail. The stage-zero Haxe compiler creates a bytecode image. A source-free
`BootRuntime` can execute the compiler in that image to produce a new bytecode
image from the exact same source text. Running the compiler from the newly
produced image must repeat the result.

## Contract

Let `H(S)` denote the reference Haxe compilation of standard-library source S,
`N(I,S)` denote the Nail compiler's image generated while booted from image I,
and `tape(I)` the sequence of postfix records in the image.

The v0.15 fixed-point checks require:

```
tape(H(S)) = tape(N(H(S), S)) = tape(N(N(H(S), S), S))
```

No normalization that silently removes bytecode differences is used. Only
JSON object member ordering is excluded from equality checks. `tape` is a
JSON array of `['L', tag, text]` and `['N', tag, childCount]` records. It is
hashed using SHA-256 for human-readable cross-target verification.

If the first mismatch occurs, the new command reports the first differing
record-tape character offset and local text excerpts.

## Implementation

- `src/nail/Rebootstrap.hx`: fixed-point verification, portable tape comparison.
- `src/RebootstrapImageMain.hx`: source-free image regenerator on Haxe CLI.
- `src/RebootstrapTestMain.hx`: rebuild stage 1 and stage 2 on Haxe, JS, PHP;
  run smoke programs from a newly-generated image.
- `rebootstrap-*.hxml`: build targets with `-D nail_seed_only`.
- `.github/workflows/nailseed-v015.yml`: checks and publishes both reference
  and Nail-generated images.

## Limitations

A reference stage-zero image is still required: this checks **rebootstrap
reproducibility**, not an image-free self-hosting process, proof of compiler
correctness, or complete elimination of the Haxe toolchain.

As in v0.14, the ByteVM is not a sandbox for untrusted user programs.

The boot distribution HXML targets embed the stage-one `self-image.json`,
ensuring the shipped runtime starts from a Nail-generated image.

## CI cost tradeoff

Haxe and JavaScript repeat both full self-compilation stages. PHP loads the
verified `self-image.json`, compares the canonical tape/fingerprint, and runs
real Nail programs via its compiler. Full PHP regeneration remains available
with the extra Haxe define `full_rebootstrap`; it is intentionally not on the
regular CI critical path due to performance.
