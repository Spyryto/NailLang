# NailSeed v0.12 — explicit continuations

The expression AST remains Literal / Var / Lambda / Apply / If. In Vm.hx an iterative CEK evaluator keeps (expression, environment, result, continuation stack). Its continuations are NeedArgument, ApplyFunction and ChooseBranch. Closure calls replace the active expression/environment; native calls return a value in-place.

The structured bytecode instruction set remains CONST / LOAD / CLOSURE / CALL / TAIL_CALL / BRANCH / RETURN. ByteVm.hx uses one instruction loop with (code, program counter, environment, operand stack, needsReturn) and a separate array of ByteFrame records. Non-tail CALL and BRANCH push saved activations. Tail CALL and terminal BRANCH replace the active block. Values completed by RETURN or by the end of a non-tail expression block are delivered to the saved caller; no Haxe/JS/PHP recursion is used for nested bytecode calls.

Malformed instruction arities, stack underflow, missing RETURN, invalid tail-call positions, or instructions after RETURN remain rejected. Interpreter instruction budgets continue to apply.

Additional tests cover a long self-tokenized/self-parsed input, deep non-tail AST and bytecode recursion, mutual tail recursion, a large Nail-compiled program, a bytecode-bootstrapped Nail compiler operating on a large program, and both step-budget guards. The historical suites are retained.

This is **not** a completely iterative toolchain: Haxe Parser, SyntaxBridge, SyntaxEncoder, TypeChecker and some AST structural helpers still recurse. Extremely deep nested syntax trees may overflow while converting or type-checking, and non-tail source recursion uses linear heap continuations.
