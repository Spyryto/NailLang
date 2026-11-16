# NailSeed v0.10 — a compiler written in Nail

This release introduces a **structured stack bytecode** and a compiler **implemented in Nail itself**, while leaving the five-node surface AST unchanged.

- `stdlib.nail` now defines `compileExpr`, `compileForm`, `compileSyntax`, `compileSource` and their helpers. It produces immutable `Syntax` values representing the bytecode — **no Haxe opcode-emission primitive is needed**.
- `src/nail/ByteVm.hx` executes compiled instructions with a private operand stack and lexical closures.
- `src/nail/BytecodeCompiler.hx` is an independent Haxe reference compiler used for equivalence tests.
- `src/BytecodeTestMain.hx` checks instruction tree equivalence, runtime equivalence, invalid bytecode and the compiler-bootstrap experiment.
- The AST stays at five constructors: `Literal`, `Var`, `Lambda`, `Apply`, `If`.

## Why structured bytecode?

Instead of encoding branch offsets immediately, the first bytecode version uses `BRANCH(thenCode, elseCode)`, and `CLOSURE(param, code)` stores its nested instruction block. This is still executable stack bytecode, but is dramatically easier to generate and validate in pure Nail. We can flatten it to jump offsets later without changing Nail's semantics.

| Opcode | Stack effect / meaning |
|---|---|
| `CONST(literal)` | Pushes a literal |
| `LOAD(var)` | Pushes the value of a lexically resolved name |
| `CLOSURE(param, code)` | Captures the current environment and pushes a callable closure |
| `CALL` | Pops argument and function, pushes result |
| `BRANCH(yes, no)` | Pops a Bool, evaluates only the selected code, pushes its value |
| `RETURN` | Returns the single stack value |

Top-level `DEFINE(name, code)` and `EVAL(code)` are *program forms*, not expression opcodes.

## Build and tests

Requires Haxe 4.3.7. Run from this directory:

```sh
haxe bytecode-test-interp.hxml
haxe bytecode-test-js.hxml && node build/tests/bytecode.js
haxe bytecode-test-php.hxml && php build/tests/php-bytecode/index.php
```

Existing v0.9 regression suites are retained. GitHub Actions runs all tests and produces JavaScript and PHP distributions. The generated runtimes remain untracked.

### JavaScript

```js
const vm = NailSeed.create(10000000);
vm.loadStdlib();
const program = vm.compileWithNail('def twice x = x * 2 ; twice 7 ;');
const byteVm = NailSeed.createByteVm(10000000);
byteVm.runPlain(program); // [14]
```

### PHP CLI

```sh
php build/php/index.php --bytecode example.nail
```

This CLI mode compiles the **user program** with the Nail-written compiler, then executes it with the bytecode engine. The standard library is currently bootstrapped with the Haxe reference compiler to avoid parsing its entire recursive source with Nail in one call; the program can use its definitions.

## Bootstrap status

The Haxe host parser still loads the source for `stdlib.nail`. The Nail-written parser and compiler generate bytecode that is executed by Haxe `ByteVm`. The bootstrap test compiles the compiler's own library definitions with the **Nail-written compiler**, runs them on `ByteVm`, and invokes that bytecode-compiled `compileSource` on a fresh small Nail program. The initial library AST is supplied by the Haxe parser/`SyntaxEncoder`, since the recursively implemented Nail lexer cannot scan a long source file in one call yet. This is **not** independent self-hosting.

Other known limits: bytecode uses Syntax trees rather than compact bytes; no verifier for resource limits; no tail-call optimization, modules, rational numbers, or standalone executable.
