# NailSeed v0.19 — ADTs in Nail + exhaustive pattern checks

This version advances [v0.18](../v0.18/): the **Nail-written parser and bytecode compiler** now support algebraic sums and constructor matches. The Haxe type checker rejects missing alternatives, wrong binding arity, and mixed-type branches.

```nail
type Option a = None | Some a ;
def valueOrZero option = match option with
  | None -> 0
  | Some value -> value ;
valueOrZero ( Some 9 ) ;

type Result a e = Ok a | Error e ;
```

A non-exhaustive `match` now reports a static error when checked:

```nail
type Option a = None | Some a ;
match ( Some 1 ) with | Some value -> value ;
# Type error: non-exhaustive match for Option: missing None
```

## Implementation

- `stdlib.nail`: tokenizer/Pratt parser for `SumType`, constructor match lowering, generated constructor functions, discriminators and positional getters, and bytecode generation — **implemented in Nail**.
- `TypeChecker.hx`: constructor registry and a host-stack-safe AST walk that recognizes the private lowering of a sum match, verifies exhaustiveness, tag ownership, and payload binding arity. It runs for both `check()` and `checkSyntax()` and persists transactionally across successful incremental checks.
- The five core expression constructors (`Literal`, `Var`, `Lambda`, `Apply`, `If`) and the structured bytecode ISA remain unchanged. Tagged values still use the nominal immutable `Record` representation.
- `AlgebraicSelfTestMain.hx`: syntax-equivalent parser results, byte-for-byte equivalent bytecode from Nail and Haxe, ByteVM execution, bootstrap without the Haxe parser, inferred types, incomplete matches, and regression errors on Haxe/JS/PHP.

`person . name` remains the surface record projection; `Person.name` remains the internal getter convention. The exact-number v0.16 experiment remains separate.

## Limitations

- Constructor field types remain single tokens: e.g. `Some a` but not `Some ( Option a )`. Parameterized recursive sum types are not yet supported.
- Constructor names are global and unique. Nested pattern syntax, record destructuring, and catch-all variants are deferred.
- Exhaustiveness is checked by the optional **Haxe Hindley–Milner checker** (including `checkSyntax()` for Nail-produced trees). The Nail-written compiler itself does not yet type-check; callers that skip checking can still reach the existing runtime `#sumFail` safeguard.
- The full Nail self-parser/bytecode pipeline is correctness-first, not a performance optimization.

## Test

```sh
haxe seed-image.hxml
haxe algebraic-self-test-interp.hxml
haxe algebraic-self-test-js.hxml && node build/tests/adt-self.js
haxe algebraic-self-test-php.hxml && php build/tests/php-adt-self/index.php
```

The v0.19 CI also runs all inherited regression suites and rebootstrap fixed-point verification.
