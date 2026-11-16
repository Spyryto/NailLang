# NailSeed v0.10 — Structured bytecode specification (experimental)

## Goals and invariants

1. Nail source remains functional and never exposes its execution stack.
2. `Expr` still has exactly five constructors (`Literal`, `Var`, `Lambda`, `Apply`, `If`).
3. The compiler is written in Nail, and emits structured instructions as first-class immutable `Syntax` values.
4. Haxe implements the executor and a separate reference compiler, **not** the production source-to-bytecode translator.
5. The compiled backend shares primitive arithmetic, text, Syntax and list implementations with `Vm.primitive`, to avoid semantic drift between AST and bytecode execution.

## Serialized representation

The object graph is `SyntaxNode(tag, List<Syntax>)` / `SyntaxLeaf(tag, Text)`. A complete program is

```text
Bytecode [ Define(Name, Code) | Eval(Code) ... ]
Code     [ Instruction ... ]
```

The instruction set is:

```text
CONST(Literal)              // push literal (number, bool, text, nil)
LOAD(Var)                   // push lexically resolved name
CLOSURE(Name, Code)         // push closure with captured lexical environment
CALL                        // pop arg, pop fn, push fn(arg)
BRANCH(Code, Code)          // pop Bool, evaluate selected branch, push its value
RETURN                      // return exactly one stack value
```

`DEFINE(Name, Code)` installs a global name; `EVAL(Code)` evaluates a top-level expression. Both top-level blocks and closure bodies end in `RETURN`. Branch blocks produce a single value at fallthrough and do not need `RETURN`. `CALL` is eager, and partial application of built-in functions is supported. Global definitions are sequential, with recursive definitions resolved through the shared mutable root environment; local captures remain lexical.

All instructions are stack-safe for compiler output. The executor rejects stack underflow, invalid opcode names, malformed operands, non-Bool branch conditions and invalid return stack depths; it is **not** a security-hardened sandbox for arbitrary untrusted bytecode.

## Compilation rules

```text
compile(Literal v)     = [CONST v]
compile(Var name)      = [LOAD name]
compile(Lambda x e)    = [CLOSURE x (Code(compile(e) ++ [RETURN]))]
compile(Apply f x)     = compile(f) ++ compile(x) ++ [CALL]
compile(If test y n)   = compile(test) ++ [BRANCH(Code(compile(y)), Code(compile(n)))]
```

No jump-offset calculations or separate label relocation are required. Each expression emits exactly one value, provided it terminates normally. `++` is implemented with the Nail `append` function on immutable lists.

## Validation approach

- The Nail compiler's output is compared structurally to a distinct Haxe reference compiler over the AST reconstructed by `SyntaxBridge`. Because both consume the *same* parser-produced Syntax tree, hidden names generated for `match` are identical.
- Execution of compiled code is compared to AST execution for arithmetic, closures, application, recursion, lists, strings, `match`, `if` and local `let`.
- Invalid instruction trees are explicitly rejected.
- The suite bootstraps the 11 core compiler definitions, not the entire standard library: Haxe parses them into five-node AST forms, `SyntaxEncoder` makes first-class Syntax values, the Nail compiler compiles these definitions into bytecode, and `ByteVm` invokes the resulting `compileSyntax` on another small AST. Parser/lexer bytecode bootstrap is intentionally deferred due to recursion depth. No Haxe code emits instructions on this production compilation path.
- The existing runtime/parser/Hindley–Milner regression suites still run on Haxe `--interp`, JS and PHP.

## Limitations

This format is a **structured intermediate bytecode**, not a compact binary file. It is intentionally easy to emit and inspect in Nail. The next steps are a bytecode verifier, a flattened indexed instruction stream, tail calls, and reducing the Haxe bootstrap. Numbers remain IEEE-754 finite floats; exact rational arithmetic has not been included. For the PHP `--bytecode` CLI, the *standard library bootstrap* currently uses `BytecodeCompiler` in Haxe; user input is compiled by `compileWithNail`. No changes are made to the previous historical NailVM ISA.
