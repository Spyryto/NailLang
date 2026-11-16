# NailSeed v0.9 — parser/AST execution boundary

## Invariant

The executable expression AST still has exactly five constructors: `Literal`, `Var`, `Lambda`, `Apply`, `If`. `Define` and `Evaluate` are top-level forms. The first-class value `Syntax` is structurally separate from the core AST, with `SyntaxLeaf(tag, text)` and `SyntaxNode(tag, children)`.

## Pipeline

```text
Source text
  -> lexNormal / lexQuoted / lexComment (in Nail, stdlib.nail)
  -> Pratt parser + match desugaring (in Nail)
  -> immutable Syntax Program (Nail value)
  -> SyntaxBridge.forms() (Haxe representation validator)
  -> existing five-node AST
  -> existing Vm evaluator or Hindley-Milner checker
```

The Haxe parser is used only to bootstrap the library and to run normal `.run()` calls. `.runWithNail()` doesn't parse the user's source with the Haxe parser, but its Haxe runtime still contains the bridge and evaluator.

## Strings and lexing

A token begins and ends at whitespace boundaries; the `"` token is a special quoted-text delimiter. The source lexer is implemented in Nail using `textAt`, `textLength`, `textConcat`. Quoted strings can contain spaces; common JSON-style one-letter escapes are supported. Unknown escapes and unterminated quotes are rejected. To remain compatible with v0.8, unescaped whitespace inside a string is collapsed to spaces and leading/trailing whitespace is ignored. Unicode/`\\uXXXX` remains deferred; ASCII-only is enforced by the existing text primitives.

## `match`

The Nail parser accepts two exhaustive list patterns in either order, exactly as the Haxe bootstrap parser does. It desugars matches into nested lambda applications, `If`, and internal list primitives. Internal names are hidden from user-written source. The implementation uses a fixed hidden name inside every *new lexical scope*; nested matches are safe because those names don't escape their scopes. The cross-parser comparator alpha-normalizes hidden `#nail_*` names when comparing the ASTs built by the Haxe and Nail parsers.

## `SyntaxBridge`

Only recognized Syntax tags with correct arity and types cross into executable AST. Bogus tags, malformed child lists, nonfinite numbers, parse errors and inappropriate literal kinds are rejected. It is a semantic validator, **not** a compiler and not a second source parser. `TypeChecker.checkSyntax()` supports inference on exactly these reconstructed forms.

## Limitations

- No true self-hosted compiler or independent Nail executable.
- No ad-hoc strings without separating the quote tokens; no significant whitespace preservation beyond escaped whitespace.
- No Unicode text/scalar indexing or rational arithmetic.
- No source locations or robust recovery diagnostics.
- Recursive source parser relies on host call stack and a finite step budget; it is not hardened for untrusted code.
- Both backends must pass the shared CI tests; distribution output is not checked into Git.
