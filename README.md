# NailSeed v0.17.1 — Explicit record-field projection

A syntax-focused follow-up to [v0.17](../v0.17/). The runtime retains the **same five expression AST forms**, nominal records, and the same bytecode.

```nail
type Person { name Text age Number } ;
def mario = Person " Mario " 34 ;
mario . name ;       # "Mario"
mario . age + 1 ;    # 35
```

Nested access is also supported, e.g. `person . address . city`. The dot is a separate whitespace-delimited token. It binds **tighter than application**: `f p . name` parses as `f ( p . name )`, so use `( f p ) . name` to access the result of `f`.

Both the Haxe and Nail-written parsers lower projection to `#recordGet`, a pre-existing primitive. No new core AST variant or bytecode instruction is introduced. The generated `Person_name` accessors still exist for compatibility.

## Type inference

For a receiver statically known to have nominal type `Person`, the inference is **just as precise** as `Person_name person`. For an unconstrained parameter, a uniquely named field determines the nominal record type; when several record types share a field name, the checker reports an ambiguity rather than choosing one. Row polymorphism and structural subtyping are not supported yet.

## Tests

```sh
haxe seed-image.hxml
haxe record-test-interp.hxml
haxe record-test-js.hxml && node build/tests/records.js
haxe record-test-php.hxml && php build/tests/php-records/index.php
```

CI exercises Haxe, Node and PHP together with previous regressions. Rational numbers remain a separate v0.16 experiment.