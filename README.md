# NailSeed v0.17.2 — Qualified internal record accessors

A naming follow-up to [v0.17.1](../v0.17.1/). User-facing syntax remains `person . name`; internally, record declarations now generate **`Person.name`** and **`Person.age`** instead of underscore names.

```nail
type Person { name Text age Number } ;
def mario = Person " Mario " 34 ;
mario . name ;   # "Mario"
mario . age ;    # 34
```

The Haxe reference compiler, Nail-written compiler and Hindley–Milner checker use the same `Type.field` key. The source-level dot remains an independent whitespace-separated token; the qualified internal name `Person.name` cannot be used as a source-level identifier. It is generated during lowering and exposed to tooling via e.g. `typeChecker.signature("Person.name")`.

`person . name` still lowers to the existing private `#recordGet` call and the type checker uses `Person.name`'s signature to validate it. No new AST variant, bytecode opcode, macro, or VM primitive is needed.

**Compatibility:** `Person_name` and `Person_age` are no longer auto-generated in this experimental version. The previous versions remain preserved. Names like `Person_name` can now be used independently without conflicting with field accessors.

The v0.16 exact-numbers laboratory remains separate.

## Tests

```sh
haxe seed-image.hxml
haxe record-test-interp.hxml
haxe record-test-js.hxml && node build/tests/records.js
haxe record-test-php.hxml && php build/tests/php-records/index.php
```

CI also runs all inherited suites and verifies the bytecode produced by both compilers on Haxe, Node.js and PHP.
