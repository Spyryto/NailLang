# v0.29 experimental numeric integration contract

## Release status

This is an **opt-in host-side numeric prototype** and portability test suite,
not yet a replacement for the main Nail compiler's floating `Number`. A
complete 0.29 implementation must still wire exact numbers through parsing,
typing, the Nail-written compiler, both execution engines, serialization and
bootstrap fixed-point tests. Nothing in this experiment silently upgrades
existing programs.

## Value representation

`FastValue = Small(Int) | Fraction(Rational) | Approximate(Float)`

The `Small` range is **[-2²⁶, 2²⁶]**, deliberately smaller than Haxe's
signed 32-bit Int. All computations that would escape the range are sent to
`Rational` *before* native arithmetic that might overflow; a rational with
denominator 1 and magnitude back in range is demoted automatically. No
distinction between compact and large representation should be observable to
Nail code: exact comparison, equality, serialization and division agree.

The compact limit is an **implementation detail**, not a language-level
`Int` maximum. No public separate `Int` type has been chosen.

## Dialect opt-in

- Unmarked source and `# nail: 0.27` select legacy floating behavior in the
  **NumericDialect laboratory adapter only**.
- `# nail: 0.29` on the first nonempty line selects exact arithmetic.
- Unsupported headers are rejected instead of falling back.
- A later header cannot retroactively change the version of a file.
- Compiler release, source dialect, numeric wire representation and bytecode
  format remain separately versioned.
- Mixed-dialect imports are **not yet supported**: before runtime migration,
  specify explicit conversion or reject cross-dialect numeric APIs.

The first-line parser prototype intentionally supports a subset of the full
language literal grammar. Actual source compilation must run its existing
parser, and must not treat this adapter as that integration.

## Exact serialization

Canonical wire format `E:[-]numerator/denominator`, where both magnitudes
are base-ten ASCII integers, denominator positive, gcd=1, zero represented
`E:0/1`, and signs never appear on a zero value. The compact/large variant
is excluded from the wire to make its optimization transparent.

Never encode large exact values through JSON numeric fields; use text.
The current canonical format is experimental, not the final bytecode format.
A future bytecode version marker must prevent legacy readers from silently
interpreting exact numbers as binary Float.

## Precision and safety

- All four basic operators are exact for exact operands.
- For division, an exact integer quotient remains `Small` if it fits.
  Nonintegral results become canonical `Fraction`.
- Comparing or operating on exact and approximate values requires a
  deliberate conversion. No automatic widening to Float.
- Indexing requires a nonnegative exact integer strictly below the
  collection length. Approximate and fractional indices are rejected.
- Approximate results are restricted to finite Float; neither NaN nor
  Infinity is silently accepted here.
- `FastNumber` retains a bounded digit budget and conservative preflight
  before BigNat work. This is *not* a total time/space budget; a production VM
  will need instruction/heap limits and optimized big-integer algorithms.

## Tests and decision gate

Haxe interpreter, Node.js and PHP must agree on:

1. Exact canonical results, mixed small/large arithmetic and comparison.
2. Input/operation size errors and index semantics.
3. Explicit source-dialect selection and strict version failures.
4. Stable round-trip wire encoding, with invalid/noncanonical input rejected.
5. Independent `Rational` and Python Fraction oracle parity.
6. Ordinary Small arithmetic measurements vs pure Rational/Float on all
   three targets, plus a real numeric workload, multiple warmups and
   allocation measures before deciding whether to switch the VM.

## Architecture work remaining

The first compiler-enabled exact dialect should add a new `Value` variant
and a bytecode numeric tag *behind* the opt-in source dialect rather than
reinterpret the existing `Number` constructor. That allows old compiled
images to remain valid and makes explicit conversions visible in typing.

Until those integration tests pass, this snapshot is not the full 0.29
language milestone; it is the validated numerical substrate.
