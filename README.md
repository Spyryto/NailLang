# NailSeed v0.32 — recoverable Result slice

This independent snapshot builds on v0.31. It adds a **typed recovery
boundary**, without changing the five-expression AST, bytecode format, or
default numeric semantics.

## What is implemented

- `examples/error-results.nail` is a real, checked Nail program defining
  `Result a e = Ok a | Err e` and a finite error ADT.
- Ordinary functions implement `resultMap`, `resultBind`, `resultMapError`,
  `unwrapOr`, domain error reporting and safe division. A normal
  zero denominator is represented by `Err DivideByZero`; it is not
  an exception. Function application and pattern matching need no new opcode.
- `ModuleBundle.tryInvoke(module, symbol, argument)` returns the Haxe
  `ModuleCallOutcome` tagged union: `CallSuccess(Value)`,
  `MissingModule(name)`, or `MissingExport(module, symbol)`.
  `ModuleBundle.invoke` remains unchanged.
- **Runtime faults propagate.** Neither a VM budget breach nor a bad
  image nor a division-by-zero thrown by a function is caught and
  disguised as a domain-level `Err`. Host callers must treat compiled
  images as trusted and uphold typed exported contracts.
- Cross-target tests compare AST and source-free/bytecode execution, typed
  inference, and separately compiled host module lookup outcomes.

### Example

```nail
type Result a e = Ok a | Err e ;
type MathError = DivideByZero | NegativeInput ;

def safeDivide n d =
  if d == 0 then Err DivideByZero else Ok ( n / d ) ;

def resultBind r next =
  match r with
  | Ok value -> next value
  | Err error -> Err error ;
```

A full example with safe composition is in
[examples/error-results.nail](examples/error-results.nail).

## Checks

After `haxe seed-image.hxml`, run:

```sh
haxe result-test-interp.hxml
haxe result-test-js.hxml && node build/tests/result.js
haxe result-test-php.hxml && php build/tests/php-result/index.php
```

The v0.32 workflow also inherits the entire v0.31 regression suite.

## Deliberate limits

This milestone is a **first slice**, not a claim of complete error effects.
Nail's `Result` is defined by each program, not a prelude namespace.
Module manifests still forbid cross-module nominal ADTs, so a public
`Result[T,E]` module ABI must follow public nominal type interfaces.
The host `tryInvoke` union is not a new Nail expression or a blanket
exception catcher. Rich diagnostic spans and capability-based I/O remain
future work.
