# NailSeed v0.4 — Haxe-first runtime

A port of the **v0.3 semantics** to a single, strongly typed Haxe implementation. The evaluator, lexer/parser and target-independent value model are all Haxe. It compiles to JavaScript and PHP, and can run with the Haxe interpreter.

## Project map

- `src/nail/Ast.hx`: exactly **five** expression constructors and two top-level program forms.
- `src/nail/Parser.hx`: whitespace tokenization, precedence parsing, desugaring into core AST.
- `src/nail/Value.hx`, `Env.hx`, `Vm.hx`: values, lexical environments, evaluation and primitives.
- `src/Main.hx`: public `NailSeed.create()` API for compiled JS; PHP main entry point.
- `src/TestMain.hx`: single test runner for all targets.
- `stdlib.nail`: 7 functions implemented in Nail, including `map`, `filter`, `fold`.
- `cases.json`: the unchanged v0.3 test corpus (24 positive / 12 negative).
- `*.hxml`: build/test recipes; `build/` is ignored.

## Build locally

Requirements: Haxe 4.3.7, Node.js and PHP 8; **no haxelibs**.

```sh
cd v0.4
haxe test-interp.hxml
haxe test-js.hxml && node build/tests/test.js
haxe test-php.hxml && php build/tests/php/index.php
haxe js.hxml
haxe php.hxml
```

JavaScript: `build/js/nailseed.js`. PHP: the **entire** `build/php/` directory (Haxe generates a multi-file application). You can run `php build/php/index.php example.nail` to execute a Nail script; it prints JSON values. Without an argument, the PHP entry point is silent.

GitHub Actions executes all three test modes and publishes separate downloadable **JS** and **PHP** build artifacts. Generated files are **not committed** into Git.

## Example Nail

```nail
def twice x = x * 2 ;
map twice [ 1 , 2 , 3 ] ;
```

Compile first; the standard library is embedded as a Haxe resource (via `-resource`). The JS API exposes `NailSeed.create()` and returns a VM with `run(source)`, `runPlain(source)`, `loadStdlib()`, `names()`; `runPlain` returns JSON-compatible results, while `run` returns tagged Haxe values. Generated JS API surface and Scriptable integration still need explicit device testing.

## Scope and caveats

The VM exposes no stack operations. Lists now use **persistent cons cells**: `cons`, `head`, `tail` are O(1), instead of copying entire JS arrays as in v0.3. List literals, comparisons and JSON serialization are O(n). Like v0.3, the evaluator is eager, recursive, dynamically typed as a **language**, has no tail-call optimization and should not execute untrusted code. Haxe's static typing checks the implementation, not Nail programs.

Do not hand-edit compiled JS/PHP. Modify the Haxe sources and let GitHub Actions rebuild both targets.
