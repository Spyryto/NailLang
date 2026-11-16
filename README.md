# NailSeed v0.9 — executing the Nail-written parser

The parser in `stdlib.nail` now accepts **quoted text literals**, **line comments** and **exhaustive list matching** (`match ... with | [] -> ... | h :: t -> ...`) in addition to the v0.8 expression grammar.

Most importantly, the Haxe runtime provides a **validated Syntax-to-AST bridge** (`SyntaxBridge.hx`) so an AST emitted by the Nail parser can be executed by the existing five-constructor VM. It does *not* reparse the source with Haxe:

```haxe
var vm = new nail.Vm(10000000);
vm.loadStdlib(); // Haxe bootstrap loads the Nail standard library
vm.runPlainWithNail('def twice x = x * 2 ; twice 5 ;'); // [10]
var tree = vm.parseWithNail('match [ 3 ] with | [] -> 0 | h :: t -> h ;');
vm.runSyntax(tree); // [Number(3)]
```

The optional type checker also supports `checkSyntax(tree)`. Both consume the same `Syntax` tree.

## Source conventions

- Every ordinary token must be separated by whitespace; string delimiters `"` must also be separated from nearby tokens.
- Quoted strings support embedded spaces and `\\n`, `\\r`, `\\t`, `\\"`, `\\\\` (ASCII only).
- `#` starts a comment at a token boundary outside a string.
- The self-parser normalizes whitespace within plain quoted strings just as the existing Haxe bootstrap tokenizer does.
- Patterns are the same two exhaustive list branches from v0.6: empty and `head :: tail`, in either order. `_` discards an element.

No numeric representation changes: numbers are still IEEE-754 floats. Exact rationals are explicitly **out of scope** for this version.

## Tests

From `v0.9/`, with Haxe 4.3.7:

```sh
haxe test-interp.hxml
haxe type-test-interp.hxml
haxe parser-test-interp.hxml
haxe self-parser-test-interp.hxml
```

GitHub Actions performs the same regressions for Haxe `--interp`, Node.js and PHP. See `self-parser-test-*.hxml` and `src/SelfParserV09TestMain.hx` for the cross-parser, malformed-input, executable Syntax and type-checker tests.

The bootstrap remains Haxe and there is no self-hosted compiler or independent binary yet. The aim of this milestone is **self-parsed execution**, not full self-hosting.
