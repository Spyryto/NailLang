# NailSeed v0.17 — Nominal immutable records

One portable **Haxe** implementation, compiled to JavaScript and PHP by GitHub Actions.

## Why records now?

Nail previously had immutable linked lists but no user-defined product types. This experiment adds **nominal** records while keeping the execution core at **five Expr variants** and the structured bytecode unchanged. Unlike `head`/`tail` traversal, fields are retrieved by hash lookup (average O(1)).

```nail
type Person { name String age Number } ;
def ada = Person " Ada " 32 ;
Person_name ada ;     # "Ada"
Person_age ada ;      # 32
```

Nail currently requires whitespace around **all** punctuation, including string delimiters and semicolons. `String` is an alias for the existing `Text` type; `Bool` and `Number` are also supported. In this version a field may reference a record type declared **earlier** in the same compilation/checker session, but not itself or a later type.

```nail
type Address { city Text } ;
type Person { name Text age Number address Address } ;
def p = Person " Ada " 32 ( Address " Venice " ) ;
Address_city ( Person_address p ) ;
```

A type declaration generates a curried constructor `Person : Text -> Number -> Person` and accessors `Person_name : Person -> Text`, `Person_age : Person -> Number`.

Records are immutable Nail values with nominal tags. Structural field equality is available only for records of the **same type**. Accessing a missing field throws a runtime error; constructing with the wrong type is rejected by the **optional static checker** (not by the untyped evaluator).

## Implementation

- `src/nail/RecordLowering.hx`: desugars a type declaration into ordinary `Define` functions and the existing `Lambda`, `Apply`, `Var`, `Literal` AST nodes.
- `src/nail/Value.hx`: one new **value** variant, `Record(typeName, fields)`, with an internal `StringMap<Value>` constructed once and never exposed to Nail.
- Two *private* primitives: `#recordMake` and `#recordGet`, needed by generated definitions. Not callable directly in surface Nail source.
- `src/nail/TypeChecker.hx`: nominal `TRecord(name)` plus generated constructor/accessor signatures and transactional type declaration checking.
- `src/nail/Parser.hx` and `stdlib.nail`: **both** the host-bootstrap parser and the Nail-written parser understand `type` and produce a `RecordType` program form. The Nail compiler expands it into ordinary `DEFINE` instructions (no new opcode).
- `src/RecordTestMain.hx`: runtime, type inference, error handling, bridge/encoder, self-parser and source-free bootstrap checks.

## Test locally (Haxe 4.3.7)

From `v0.17`:

```sh
haxe seed-image.hxml
haxe record-test-interp.hxml
haxe record-test-js.hxml && node build/tests/records.js
haxe record-test-php.hxml && php build/tests/php-records/index.php
```

The workflow `.github/workflows/nailseed-v017.yml` runs these tests and all v0.15 regression suites on Haxe/Node.js/PHP, and produces JS/PHP release artifacts.

## Intentionally not implemented

- Generic parameterized records, recursive user-defined record types, ADTs/sum types, pattern matching on record fields, record update syntax.
- `Vector` indexing and macros: separate future experiments.
- Exact rational arithmetic of the isolated v0.16 experiment: v0.17 still uses the floating-point Number semantics inherited from v0.15.

This version is experimental; record declarations are versioned independently of the future stabilized Nail language specification.
