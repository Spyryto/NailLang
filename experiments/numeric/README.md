# NailSeed v0.29 — Compact exact-number and source-dialect prototype

This is a **separate, experimental language-integration stage** derived from
[v0.28](../v0.28/). It does **not** change the established Nail compiler,
type checker, bytecode interpreter or `Value.Number(Float)` representation.
It isolates the semantics and portability requirements needed before a
backward-compatible runtime migration can be attempted.

## What's new

- `FastNumber` represents an exact number as either `Small(Int)` or a
  canonical `Fraction(Rational)`. An explicit `Approximate(Float)` remains
  a separate domain. No implicit exact/Float mixing.
- Small integers are limited to the signed range **±67,108,864 (2²⁶)**.
  Addition, subtraction, multiplication and division use fast native integer
  operations only when the result is provably representable in that range.
  This is designed to avoid overflow even in the Haxe interpreter. Anything
  else enters the already tested arbitrary-precision rational implementation.
- Exact operations enforce operand/output digit limits and a conservative
  work-budget preflight for large-number calculations. The work budget is
  **not** yet a full execution-time/memory quota.
- The v0.29 copy of `Rational.add` avoids unnecessary cross-products for
  canonical fractions sharing a denominator. The 512-beat tempo workload
  demonstrates this optimization on all three targets.
- Source-dialect adapter `NumericDialect.detect` defaults to legacy Float
  semantics. The header `# nail: 0.29` explicitly opts into exact arithmetic
  **only through this experimental adapter**. The live Nail source parser does
  not yet enforce or interpret the new dialect.
- `FastNumber.encodeExact/decodeExact` uses canonical, text-based `E:n/d`
  wire values. Never transport a large exact numerator or denominator as a
  JSON number. Old bytecode images are unchanged.

### Example (Haxe host-side prototype)

```haxe
import numeric.FastNumber;
import numeric.NumericDialect;

var sum = FastNumber.arithmetic(
  "+", FastNumber.exact("0.1"), FastNumber.exact("0.2"));
trace(FastNumber.encodeExact(sum)); // E:3/10

trace(NumericDialect.describe(NumericDialect.evaluate(
  "# nail: 0.29\n0.1 + 0.2 ;", "0.1", "+", "0.2")));
// exact:E:3/10

// Without a header the adapter keeps the old Float semantics.
```

## Tests

```sh
# Inside v0.29/, with Haxe 4.3.7:
haxe test-interp.hxml
haxe test-js.hxml && node build/numeric-lab.js
haxe test-php.hxml && php build/php/index.php
haxe candidate-test-interp.hxml
haxe candidate-test-js.hxml && node build/numeric-model.js
haxe candidate-test-php.hxml && php build/php-numeric-model/index.php
haxe numeric-fast-test-interp.hxml
haxe numeric-fast-test-js.hxml && node build/fast-numeric.js
haxe numeric-fast-test-php.hxml && php build/php-fast-numeric/index.php
```

The GitHub workflow reads all 270 committed independent Python Fraction
reference cases (no Python runtime needed), then runs the inherited v0.28
tests and new parity/property-style tests. New tests cover
promotion at the signed 2²⁶ boundary, large exact products, canonical
wire round-trips, invalid indices/headers, exact/Float isolation, and a
three-way fast-integer / pure rational / Float microbenchmark. It also
compares a **144-line invoice** and a **512-beat musical timeline** across
compact exact, pure Rational and Float on all three targets. Diagnostic
counters track fast paths and fallback conversions, not actual heap allocations.

See [SPEC.md](SPEC.md) for numeric opt-in compatibility requirements and
[WORKLOAD-BENCHMARKS.md](WORKLOAD-BENCHMARKS.md) for the invoice and musical
timeline measurements, including counts of integer and rational paths.
Earlier exploratory measurements are in
[v0.28/BENCHMARK-RESULTS.md](../v0.28/BENCHMARK-RESULTS.md).

## Explicit limits and next integration steps

A small-integer fast path removes unnecessary arbitrary-precision allocations
for ordinary arithmetic but **is not proof** that a unified exact `Number`
is now optimal for all workloads. It also does not make decimal-string
BigNat/GCD algorithms fast for huge fractions.

Before declaring v0.29's intended **full numeric integration** complete,
we still need:

1. Source-language dialect metadata carried through modules, imports and
   the self-hosted compiler, with explicit incompatibility diagnostics.
2. Type inference/operators that distinguish exact `Number` and `Float`.
3. New VM value variants and a backward-compatible serialized bytecode
   format; test both Nail-written compiler and Haxe reference compiler.
4. Cross-target runtime and fixed-point bootstrap tests with opted-in programs,
   plus memory allocations, adversarial workload budgets and real applications.

The current PR is intentionally **groundwork**, not a claim that those
compiler/runtime changes have already been delivered.
