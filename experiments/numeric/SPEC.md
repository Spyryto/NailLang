# Nail 0.28 proposed numeric decision gates

## Observed baseline

- v0.26 and v0.27 still use `Value.Number(value:Float)` and
  `NType.TNumber`; `+`, `-`, `*`, `/`, comparisons, text indexes and
  vector indexes share that representation.
- v0.16 independently proved pure-Haxe arbitrary-precision rational
  arithmetic on Haxe, JavaScript and PHP. It did not change the Nail VM.
- v0.28 adds an executable tag boundary:
  `Exact(Rational)` versus `Approx(Float)`. No silent conversion.

## Tentative preference (not yet a language decision)

Prefer **one exact Number domain plus an explicit approximate Float domain**
unless representative application workloads reveal an unacceptable overhead or
an inference/interop problem. Make integers an optimized representation of
exact rationals internally *before* multiplying public numeric types.

### Required correctness rules

- `0.1 + 0.2` evaluates exactly to `3/10` in an opted-in dialect.
- `1 / 3` is exact; division by zero fails in either domain.
- Fraction equality is canonical, ordered comparison exact.
- Floats are IEEE 754 finite values with observable rounding.
- Never silently promote exact arithmetic into `Float`; mixed operations
  require a deliberate conversion.
- Collection indexes are integral, nonnegative and in-range. Never truncate a
  rational index, and make approximate-to-index conversion explicit.
- Exact arithmetic must have operand/output digit and work budgets.
- Source-language dialect version, compiler version and bytecode image
  format must be independent.

### Language surface yet to design

- How to spell an explicit approximate literal or conversion (e.g.,
  `float 1.0` vs `1.0f`).
- Whether numeric operators are overloaded using constrained inference,
  or Float receives distinct operators/functions. Avoid silently changing the
  inferred type of existing programs.
- How `Number`, a potential `Int`, and `Float` compose in collections,
  structural records and future public type annotations.
- Mixed-version module imports and literal-version migration.
- Canonical serialization of exact numbers in syntax/bytecode, without
  JSON number precision loss; transport exact digits as text.
- Rounding policy at explicit conversion boundaries, particularly overflows,
  extremely small subnormals and huge ratios whose numerator/denominator
  cannot separately be represented by `Float`.

### Engineering risks to measure

- Pure-Haxe BigNat uses decimal digit strings and grade-school multiplication/
  division/GCD. The algorithms are intentionally simple but may be slow.
- Exact fractions can create unexpectedly large intermediate numerators and
  denominators. Budget preflight is needed *before* expensive work in a
  production implementation, not just post-operation size checks.
- A runtime `Number` representation change touches parsing, the checker,
  both VMs, equality, serialization, indexed primitives, bootstrap and host
  APIs. Do not implement any of those piecemeal in an existing dialect.

## Acceptance for moving from 0.28 to 0.29

1. Independent reference vectors and cross-target model tests green.
2. Document precision, comparison, indexing, conversion, error behavior.
3. Time representative arithmetic on Haxe/JS/PHP without imposing arbitrary
   performance claims. Investigate optimized integer fast paths.
4. Decide exact-unified vs separate numeric types, with written rationale.
5. Introduce source-dialect opt-in and stable bootstrap serialization tests
   **before** changing execution semantics.
6. Include at least one real numeric workload and an adversarial big-number
   workload. Performance and memory bounds need their own acceptance limits.

This lab is evidence for a decision, not proof that a new number model is
ready for the full Nail compiler.
