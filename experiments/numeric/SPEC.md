# Exact number experiment — specification v0.16 (draft)

## Canonical value

Every exact number is a reduced fraction `(negative, numerator, denominator)` where numerator and denominator are normalized decimal **digit strings**, denominator > 0, `negative` is a Boolean, and zero is always `(false, "0", "1")`.

The implementation never sends a whole user number through Haxe `Int` or JavaScript/PHP numeric conversions. Host `Int` is only used to calculate individual digits (0–9), carries, and indexes.

## Lexical conventions (proposed Nail dialect)

- Integer: `-?[0-9]+`.
- Rational literal: `-?[0-9]+/[0-9]+`. No spaces within the token; zero denominator rejected.
- Finite decimal: `-?[0-9]+\.[0-9]+`, converted exactly into a fraction with a denominator that is a power of 10.
- `3/4` is a literal; `3 / 4` uses the division operator.
- Normalization occurs on value creation (`6/8` -> `3/4`, `-0.0` -> `0`).
- `1e3`, `.5`, `1.`, `+2`, and non-ASCII digits are not currently accepted.
- The host lexer/runtime does **not** interpret these new literal tokens yet; this is an isolated class-level experiment.

## Operations

`add`, `subtract`, `multiply`, `divide`, `compare`, `equals`, `negate`, `toString`. All operations preserve normal form and use exact integer arithmetic. Division by zero is an error. Structural equality of two rational values equals numeric equality because every value is canonical.

Magnitude arithmetic (addition, subtraction, multiplication, quotient/remainder, GCD) is implemented in `BigNat.hx` using decimal digits and no external libraries. Division uses schoolbook long division with at most nine subtractions per generated quotient digit. Current complexity is intentionally not optimized.

## Portability and tests

54 randomly generated signed rational pairs, each used in five operations (+, -, *, /, compare), produce 270 test vectors computed **independently** with Python `fractions.Fraction`. All operands and expected results are stored as strings so no JSON numeric precision is lost. Additional smoke tests cover normalization, very large values, zero, errors and source version headers.

Haxe, JavaScript and PHP run the identical Haxe test suite via GitHub Actions.

## Constraints and decisions before integration

- Benchmark vs JavaScript `BigInt` and PHP GMP (optional performance backends) *after* the portable pure-Haxe reference is correct.
- Decide whether `Number` means exact by default in a new language version, with `Float` offered explicitly for measurements/graphics.
- Version source semantics before changing `/` or the behavior of decimal literals. Do **not** change old sources without opt-in.
- Budget instructions/allocations/digits when accepting untrusted programs; exact fractions can grow very large.
- The next major step would be a versioned lexer/Value/TypeChecker bridge, with an explicit migration rule and regression tests for pre-0.16 programs, not another rewrite of the VM.
