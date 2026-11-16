# NailSeed v0.29 — numerical workload observations

Source: [GitHub Actions run 43704531587](https://github.com/Spyryto/NailSeed/actions/runs/43704531587),
15 November 2026; all 21 CI steps succeeded. Haxe interpreter, Node.js and
PHP each passed 751 compact-number assertions, 9 workload assertions and the
inherited 333 exact-arithmetic assertions and 26 candidate-model assertions.

**These are single-run exploratory times**, not stable speed guarantees or
measurements of end-user app performance. The implementation deliberately
runs independent cross-target Haxe source without platform-specific integer
APIs.

## Test A: 144-line invoice with discount and VAT

Each line calculates an integral quantity times an integral price in cents,
then adds it to a running total. After 144 lines, apply a 5% discount and 22%
tax *exactly*. Results were checked against the original unoptimized
Rational engine. Values were not converted to Float before comparison.

| Target | Compact exact (15 runs) | Pure Rational (15 runs) | Float (15 runs) | Compact vs Rational |
| --- | ---: | ---: | ---: | ---: |
| Haxe interpreter | 22.72 ms | 398.66 ms | 0.113 ms | 17.5× faster |
| JavaScript / Node | 4.15 ms | 16.06 ms | 0.128 ms | 3.9× faster |
| PHP | 9.93 ms | 285.05 ms | 0.040 ms | 28.7× faster |

Diagnostic *execution-path* counts for one compact invoice (all targets):
**288** native small-integer arithmetic results, **2** rational operations,
**1** compact-integer-to-Rational conversion.

These counts identify potential allocation hotspots, **not measured heap
allocations**. Haxe may still allocate an enum representation for every Small
result, depending on the target.

## Test B: 128-bar musical timeline at 97 BPM

Four beats per bar, 512 beat positions, each advancing by exactly `60/97`
seconds. The exact final time is `30720/97` seconds with no rounding drift.
This is a deliberately unfavorable workload for a pure integer fast path.

| Target | Compact exact (10 runs) | Pure Rational (10 runs) | Float (10 runs) |
| --- | ---: | ---: | ---: |
| Haxe interpreter | 857.07 ms | 827.83 ms | 0.130 ms |
| JavaScript / Node | 46.88 ms | 41.81 ms | 0.098 ms |
| PHP | 682.33 ms | 656.61 ms | 0.049 ms |

Diagnostic counters: **0** Small arithmetic results, **512** rational
operations and **6** Small-to-Rational conversions across the timeline. The
compact implementation is slightly slower on this fraction-heavy path due to
the extra runtime tag and dispatch.

## Follow-up: equal-denominator rational addition

A small optimization in the **v0.29 copy only** of `Rational.add`
avoids cross-multiplying two numerators when both fractions already share
the same canonical denominator. This is common in a fixed-tempo musical
timeline. The optimization preserves every 270-vector Python Fraction oracle
result on all three targets.

Source: [GitHub Actions run 43704787005](https://github.com/Spyryto/NailSeed/actions/runs/43704787005),
all **21 steps green**.

| Target | Compact exact tempo, before → after (10 runs) | Pure Rational tempo, before → after |
| --- | ---: | ---: |
| Haxe interpreter | 857.07 → 552.39 ms | 827.83 → 535.03 ms |
| JavaScript / Node | 46.88 → 22.25 ms | 41.81 → 19.05 ms |
| PHP | 682.33 → 402.19 ms | 656.61 → 379.53 ms |

It also preserved the integer-heavy invoice's clear advantage over the pure
Rational path: Haxe 16.57 vs 422.61 ms, JS 4.86 vs 16.04 ms,
PHP 10.47 vs 290.75 ms for the same 15 invoice runs.

This does **not** make the fractional case as fast as native Float. The
fraction-heavy timeline is still substantially more expensive and the extra
tag/dispatch in the compact candidate remains a small overhead. Differences
between runs may include variance, JIT behavior and CI runner contention.

## Decision implications

The first optimization is worthwhile for **integer-heavy exact workflows**,
but it **does not solve** the cost of long rational computations or close
the gap to native Float. The next engineering focus should be numerator/
denominator cross-cancellation, GCD algorithm improvements, appropriate
big-integer representation and a richer memory/work profiling strategy.

A single benchmark runner and iteration count can exaggerate variance and
JIT effects. Repeat with independent runs, warmer runtimes, allocation
profiler output and representative apps before establishing a performance
budget or changing Nail's default `Number`.

The tested `NumericDialect` opt-in is only the host-side experimental adapter;
the existing Nail compiler, VM and source-language dialect continue using
Float. See [SPEC.md](SPEC.md) for the full migration gates.
