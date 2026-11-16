# NailSeed v0.28 — Numeric semantics decision laboratory

This is an **isolated experiment**, not an integrated Nail compiler or VM
release. The existing runtime still represents `Number` with a Haxe
`Float`. No previous source dialect or bootstrap image is changed.

## Candidates under evaluation

1. **Unified exact `Number` plus explicit `Float`**: integers, finite
   decimal literals and fractions are normalized as the same exact rational.
   `Float` is explicitly approximate, optimized for audio, graphics and
   measurement workloads.
2. **Separate `Int`, `Rational`, `Float`**: may improve integer
   indexing and specialized operations, but adds conversion and type-inference
   rules. This remains a design comparison, not yet a second implementation.

The current executable candidate explores option 1, reusing
[v0.16's pure-Haxe BigNat/Rational implementation](../v0.16/).
The `NumericCandidate` wrapper deliberately rejects implicit mixed-domain
arithmetic/equality/comparison, enforces finite approximate values, supports
an explicit (conservative) rational-to-Float bridge and requires exact
nonnegative integers for indexing.

```haxe
var a = NumericCandidate.exact("0.1");
var b = NumericCandidate.exact("0.2");
var sum = NumericCandidate.arithmetic("+", a, b);
// exact:3/10, not an approximated IEEE 754 result
var approximation = NumericCandidate.toApproximate(sum);
```

## Execute (Haxe, JavaScript and PHP)

```sh
haxe test-interp.hxml
haxe test-js.hxml && node build/numeric-lab.js
haxe test-php.hxml && php build/php/index.php
haxe candidate-test-interp.hxml
haxe candidate-test-js.hxml && node build/numeric-model.js
haxe candidate-test-php.hxml && php build/php-numeric-model/index.php
```

The repository commits the full 270-case independent arithmetic oracle,
originally generated with Python `fractions.Fraction`. Local builds and
GitHub Actions consume these fixed reference vectors directly, without Python,
and run all inherited v0.16 tests before checking candidate arithmetic,
conversions, indexing, resource errors, and simple cross-target arithmetic
benchmarks. `tests/generate_cases.py` remains an optional provenance tool.

## Constraints and benchmark interpretation

- The pure-Haxe decimal-digit algorithms prioritize portability and
  auditability, **not performance**. Benchmark output is informative only:
  there is no arbitrary target-relative speed threshold in CI.
- The wrapper limits input/output numerator and denominator sizes
  (`DEFAULT_DIGITS=128`, hard maximum `4096`). Intermediate products
  can be larger than the limit. This is not yet an instruction/memory budget
  adequate for executing untrusted programs.
- Conversion to `Float` rejects non-finite intermediate magnitudes, even if
  a huge numerator/denominator ratio would be representable. This
  conservative rule is revisable.
- Benchmark timing varies substantially by VM, JIT, host CPU and warmup.
  Allocation, memory, indexing in a real Nail runtime, and complete
  self-hosted compilation costs are **not measured** here.

See [SPEC.md](SPEC.md) for open language design choices and
[BENCHMARK-RESULTS.md](BENCHMARK-RESULTS.md) for the first measured CI comparison. **Do not change the
meaning of `Number` or `/` in the main language until source dialect
versioning, mixed-version modules, serialization, inference and bootstrap
compatibility have explicit tests.**
