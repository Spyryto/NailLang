# NailSeed v0.16 — Exact Number Lab (experimental)

This folder is **an independent experiment**, not a replacement for the v0.15 runtime or a complete v0.16 Nail compiler. Full self-hosting is intentionally deferred.

Goals:

1. Try a **single exact number model**: integers, rational fractions, and finite decimal literals all normalized as rational values.
2. Implement arbitrary-precision magnitude arithmetic in **pure Haxe**, without JS BigInt, npm packages, GMP, or other target-specific dependencies.
3. Use the **same source and independently generated test vectors** on Haxe `--interp`, JavaScript, and PHP.
4. Explore **per-source language versioning**, following the broad idea used by Dart, without changing the older language semantics yet.

## Example numeric syntax (future dialect, not currently wired into Nail)

```nail
# nail: 0.16
def thirds = 1/3 ;
def tenth = 0.1 ;
def total = tenth + 0.2 ;
# total = 3/10 exactly
```

Spaces remain the token separator. `3/4` would be one rational literal; `3 / 4` remains three tokens. Unlike the v0.15 floating-point runtime, both would be evaluated exactly in this proposed dialect.

## Source files

- `src/numeric/BigNat.hx`: normalized, nonnegative arbitrary-precision decimal integer primitives.
- `src/numeric/Rational.hx`: signed canonical fractions with a strictly positive denominator.
- `src/numeric/LanguageVersion.hx`: **standalone experimental** header recognition; NOT connected to the Nail compiler/VM.
- `src/NumericLabMain.hx`: smoke tests, errors, large numbers, version header.
- `tests/numeric-cases.json`: all 270 independently generated exact arithmetic/comparison reference vectors, committed and used unchanged by local tests and CI. The optional `tests/generate_cases.py` records their original Python `fractions.Fraction` provenance; Python is not required for testing.
- `test-{interp,js,php}.hxml`: build/test entry points.

Run the three platforms from this folder (no Python needed):

```sh
haxe test-interp.hxml
haxe test-js.hxml && node build/numeric-lab.js
haxe test-php.hxml && php build/php/index.php
```

The matching workflow under `.github/workflows/nailseed-v016.yml` verifies all three automatically.

## Important limitations

- Big integer algorithms currently operate on **decimal digit strings**; they are simple and portable, but not optimized, especially GCD/division.
- Arithmetic is exact within available memory/time; it is *not* constant-time or hardened against untrusted huge inputs.
- Floating-point transcendental functions, scientific notation, fractional exponents, and mixed approximate/exact arithmetic are deliberately out of scope.
- The existing Nail type `Number` is **unchanged**, as is the v0.15 compiler and bytecode. The header is a proof of concept only.
- Generated JS/PHP code may be larger than native implementations; size/performance should be measured on CI.

See `SPEC.md` and `LANGUAGE-VERSIONING.md` for the design decision points.
