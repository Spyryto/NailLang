# NailSeed v0.13 — Structured AST traversal with explicit frames

## Invariants

1. Core AST remains `Literal`, `Var`, `Lambda`, `Apply`, `If` and program forms `Define`, `Evaluate`.
2. The compiled bytecode remains `CONST`, `LOAD`, `CLOSURE`, `CALL`, `TAIL_CALL`, `BRANCH`, `RETURN`, plus program forms `DEFINE`, `EVAL`.
3. Child evaluation/compilation order remains left-to-right; `if` evaluates/checks its condition before the branches.
4. `let` desugars to a directly applied lambda, and generalization takes place at that boundary. A recursive global `def` remains monomorphic during inference and generalizes only afterward.
5. The host bytecode compiler and the Nail-written compiler must produce equivalent instruction trees; existing regression suites guard that behavior.

## Iterative syntax conversion

The `SyntaxBridge` and `SyntaxEncoder` both use `pending` and `values` stacks. A `(node, finish = false)` task schedules its children in reverse visitation order, followed by a `(node, finish = true)` task. The completion task pops child results and constructs the parent. This removes host-language recursion proportional to expression-tree depth. Form lists are still processed in a loop.

## Iterative inference

`Inference.infer()` is now a state machine with explicitly saved scopes and intermediate types. The four important paths are:

- Ordinary application: infer function, then argument, unify `fType` with `argumentType -> resultType`.
- Direct lambda application (local `let`): infer binding first, generalize against outer environment, then infer body with a polymorphic binding.
- Lambda: introduce fresh monomorphic parameter and infer body in a child scope.
- Conditional: require `Bool`, infer both branches and unify branch types.

Type utilities (`prune`, `occurs`, `unify`, `free`, `replacement`, `normalize`, `requireEquality`, `describe`) use stacks/worklists instead of recursive calls.

## Reference bytecode lowering

`BytecodeCompiler.emit()` performs iterative postorder lowering and preserves tail position through `Lambda` bodies and `If` branches. `Apply` in tail position emits `TAIL_CALL` instead of `CALL`; value-producing terminal expressions emit `RETURN`. No changes to the bytecode executor are required.

## Test scope

`StructuralDepthTestMain` directly constructs AST trees to stress the structural conversions independently from the still-recursive host source parser. It also checks static inference and bytecode execution on deeply nested conditions and applications, along with malformed Syntax error messages. The deep grouping test exercises an optimization in the first-stage Haxe parser, not a full iterative Pratt parser.

## Known limitations

- `Parser.expression()` and grammar-directed parsing of arbitrarily nested constructs are **not** fully iterative.
- The Nail-written bootstrap parser still runs atop the host loader. Haxe `SyntaxBridge` validates its AST, and the host type checker remains the source of static type semantics.
- Structural transformations are bounded by heap memory, and repeatedly concatenating emitted instruction arrays or copying lexical environments can be superlinear. Stack safety is not a performance guarantee.
- No arbitrary precision numbers, new source syntax or new VM operations are introduced in v0.13.
