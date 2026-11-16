# NailSeed v0.18 — Algebraic data types (Haxe-first experiment)

The next data-model step after [v0.17.2](../v0.17.2/) adds **nominal parameterized sum types**, curried constructors and constructor pattern matching:

```nail
type Option a = None | Some a ;
def valueOrZero o = match o with | None -> 0 | Some n -> n ;
valueOrZero ( Some 9 ) ;

type Result a e = Ok a | Error e ;
```

A non-generic recursive type is also possible:

```nail
type Tree = Leaf Number | Branch Tree Tree ;
```

The five core AST expressions and bytecode instruction set remain unchanged. Variants reuse the immutable nominal Record value representation with private `#tag` and positional keys. The only new primitive is the private `#sumFail`, used for unmatched cases.

**Scope boundary:** The Haxe reference parser/compiler, AST VM, bytecode VM and Hindley–Milner checker implement this feature on the JS and PHP targets. The **self-hosted Nail parser/compiler is not yet updated for sum declarations**, so the precompiled bootstrap in this iteration only supports the preceding language subset. This is a deliberately staged extension, *not* full self-hosted ADTs.

The checker infers `Some : a -> Option[a]`, `None : Option[a]`, `Ok : a -> Result[a,b]`, and validates bindings in match arms. **Exhaustiveness is not yet statically enforced**; unmatched variants throw. Constructor field types are atomic names; parameterized recursive ADTs and nested applied field types await a richer grammar. Constructors have globally unique names.

User-facing record access remains `person . name`, internally `Person.name`. Exact rational numbers remain a separate v0.16 lab.

## Test all three targets

```sh
haxe sum-test-interp.hxml
haxe sum-test-js.hxml && node build/tests/sums.js
haxe sum-test-php.hxml && php build/tests/php-sums/index.php
```

The workflow also runs all inherited regressions and the existing Nail bootstrap checks.
