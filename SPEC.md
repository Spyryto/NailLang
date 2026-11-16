# NailSeed v0.11 — Tail-aware structured bytecode

## Invariants

- Nail source syntax and five forms of core expression AST are unchanged from v0.10.
- The structured code format is still first-class `Syntax` values.
- `TAIL_CALL` is the only new opcode; non-tail `CALL` remains.
- Type inference, string and pattern parsing are unchanged.

## Tail positions

`emit(expr, tail)` generates one of the following:

- `Literal`, `Var`, or `Lambda` in tail position: evaluate and end in `RETURN`.
- `Apply(f, x)` in tail position: evaluate `f`, then `x`, then `TAIL_CALL`. No subsequent `RETURN`.
- `If(c, y, n)` in tail position: evaluate `c`, then `BRANCH` with both blocks recursively generated in tail position. The `BRANCH` terminates the enclosing block.
- Other expressions (including arguments to a tail call) compile in non-tail position.

Lambda bodies, `DEFINE` value bodies and top-level `EVAL` bodies are generated in tail position. A top-level tail invocation is completed through the same call trampoline.

## VM execution contract

A code block produces either `Done(value)` or `TailInvoke(function, argument)`. The latter is internal executor control flow, **not a Nail value** and never escapes the public API.

`ByteVm.call` maintains an iterative `(fn, arg)` pair. When a closure body emits a tail request, it updates the pair and continues. This discards the previous closure activation before entering the next one, preserving lexical captures and the global environment.

A terminal `BRANCH` in a tail block propagates either outcome directly; a non-tail branch evaluates to a normal value that is pushed on the operand stack.

Validation rules:

- `TAIL_CALL` takes zero encoded operands, consumes exactly one function and argument, and must be the last instruction of a tail-enabled block with an otherwise empty stack.
- `RETURN` must be the last instruction of a tail-enabled block and leave exactly one value.
- A branch may be terminal in a tail block; branch blocks inherit that context.
- The step budget still applies on every instruction and every call iteration, preventing a tail loop from bypassing limits.

## Tests

The Nail compiler (`compileGo` / `compileTail` in `stdlib.nail`) and Haxe reference compiler (`BytecodeCompiler.emit(expr, tail)`) must produce structurally equal instruction trees.

Regression tests include normal arithmetic, higher-order functions, closures, conditional execution, factorial (non-tail), recursive list operations, explicit tail calls, mutual tail recursion, malformed opcode placement, bounded execution, and compiler bootstrap.

A 30,000-iteration tail-recursive numeric loop and a 20,000-call mutual recursion are run in the ByteVM on Haxe, JS, PHP. These tests intentionally do not run through the recursive AST interpreter.
