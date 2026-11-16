# NailSeed v0.4 — Haxe-first runtime and shared semantics

This version preserves v0.3's source grammar and its 36 JSON cases, adding a fifth AST-coverage assertion to the test harness (37 total). Its major change is **architectural**, not surface syntax: one Haxe implementation cross-compiles to JavaScript and PHP and also runs in `--interp`.

## Core

`Expr = Literal(Value) | Var(String) | Lambda(String, Expr) | Apply(Expr, Expr) | If(Expr, Expr, Expr)`.

`Form = Define(String, Expr) | Evaluate(Expr)`. All surface features such as multi-argument definitions, infix operators, `[]` and `[ x , y ]` desugar into the five expression forms. The lexer retains the whitespace-token rule; no string literals, point-free operator sections or pipeline syntax yet.

## Values

`Value = Number(Float) | Boolean(Bool) | Nil | Cons(Value, Value) | Closure(String, Expr, Env) | Native(String, Int, Array<Value>)`.

Unlike v0.3's frozen JS arrays, lists are immutable linked cons cells. `cons`, `head`, `tail`, `isEmpty` operate on this representation. The `#cons` private alias prevents shadowing of list syntax by a user variable called `cons`. The global root environment is shared by closures to allow top-level recursion; locally bound function arguments use child environments.

The host primitives are `+ - * /`, numeric comparisons `< <= > >=`, structural equality `== !=`, list constructors/inspectors `nil cons head tail isEmpty`. Arithmetic requires finite numbers, division by zero throws, `if` requires a Boolean, equality is defined for primitive values and lists (not functions), and a step budget limits evaluation but is **not** a security sandbox. The infinite-recursion test uses a low budget (128) so the Haxe interpreter stops before its own call-stack limit.

## Common test contract

- `cases.json` is copied verbatim from v0.3: 24 positive, 12 negative.
- `TestMain.hx` loads test data and `stdlib.nail` as Haxe `-resource` files, so tests use no host-specific filesystem APIs.
- It validates the 36 cases and checks that all five AST forms are seen (37th test).
- Run the exact same runner in `--interp`, compiled JS with Node 22, and compiled PHP with PHP 8.

The source-level semantics are intentionally kept independent of JS/PHP. `haxe.Json` is only used to compare portable test outputs; Nail functions are not JSON-serializable. Generated output may differ in size/format on each target.

## Packaging

- `js.hxml`: `build/js/nailseed.js`, exported `NailSeed.create()`. The returned VM provides `runPlain()` for JSON-compatible output.
- `php.hxml`: `build/php/`, run via `php build/php/index.php example.nail` (all generated PHP files required). This CLI adapter loads the bundled stdlib and prints JSON values.
- `test-interp.hxml`, `test-js.hxml`, `test-php.hxml`: shared tests.
- `.github/workflows/nailseed-v04.yml` (repository root): Haxe 4.3.7, Node 22, runner PHP; uploads two artifacts after tests pass.

## Deferred

- Static HM inference for Nail programs, local let / pattern matching / ADTs.
- TCO and deep-recursion resilience.
- Host I/O effects, strings and a proper Scriptable API integration test.
- Nail self-hosting and native Nail bytecode.
