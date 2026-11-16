# v0.18 — Parametric sum data types

**Syntax:** `type T a b = CtorOne a | CtorTwo b ;`. Every payload field type is one token. A constructor with no payload evaluates to a value; otherwise it is curried.

**Representation:** reuse `Record(typeName, fields)` with hidden fields `#tag` and `#0`, `#1`, etc. Generated constructor predicates and getters are named `Ctor?` and `Ctor.0` internally. No new expression or bytecode case.

**Matching:** `match expr with | Ctor x -> first | Other -> second` lowers to a once-bound receiver and nested `If` expressions. A private `#sumFail` handles uncovered cases. The pattern payload projections check the constructor tag. Nested matches should be parenthesized in this version.

**Types:** `TSum(name, params)` is nominal. Hindley–Milner quantified schemes are generated for constructors, testers and accessors. Eq for type arguments is checked recursively, while the existing record equality compares the actual immutable fields. Nested applied type syntax and compile-time exhaustiveness checking are postponed.

**Bootstrap:** v0.18 keeps the v0.17.2 Nail-written standard-library parser/compiler unchanged, and thus tests new ADT forms through the Haxe source compiler. Full self-hosting of this new syntax is the next step.
