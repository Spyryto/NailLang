# v0.28 numeric benchmark — initial CI observation

Source: [GitHub Actions run 43701802048](https://github.com/Spyryto/NailSeed/actions/runs/43701802048)
on 15 November 2026. All 15 workflow steps succeeded.

This is **one exploratory run**, not a stable benchmark or a production
performance claim. Every value covers 1,200 computations of `1/3 + 1/6`
using the pure-Haxe `Rational` candidate or a Haxe `Float` (including
the `NumericCandidate.arithmetic` dispatch). Inputs were allocated before
the measured loop; result handling is included.

| Target | Exact rational (ms) | Float (ms) | Observed ratio |
| --- | ---: | ---: | ---: |
| Haxe interpreter | 31.587 | 0.800 | ~39.5x |
| JavaScript / Node.js | 19.934 | 0.452 | ~44.1x |
| PHP | 23.933 | 1.335 | ~17.9x |

The underlying implementation is pure Haxe, performing decimal-string
multiplication and long-division/GCD for each normalized rational operation.
Its primary value is correctness and portability, not speed.

All three targets also passed 333 inherited numeric assertions including
270 regenerated Python `fractions.Fraction` reference vectors, plus 26
new candidate assertions each.

## Consequences for language design

- An exact default `Number` remains a *promising hypothesis*, not an
  accepted migration.
- Prioritize a compact integer fast path and rational cancellation strategies,
  and benchmark realistic calculations plus allocation profiles before v0.29.
- Treat precision errors and implicit float mixing as correctness risks; the
  opt-in exact model already demonstrates how to avoid them.
- Keep floating-point arithmetic explicit for latency-sensitive audio/graphics.
- Retain source dialect/version isolation and canonical numeric serialization
  as nonnegotiable migration requirements.

## Limits of these measurements

One iteration-count and one runner per target; no warmup control, memory
profiling, variance intervals, compiled native targets, or real Nail VM
integration. These differences **cannot** predict the slowdown of an
optimized exact-number runtime, and a ratio does not measure user-visible
application performance. Re-run with repetitions and representative workloads
before choosing a public number model.
