# NailSeed v0.8 — Self-authored parser experiment

## Core invariant

Five executable expression cases, unchanged from the Haxe-first versions:

`Literal(value)`, `Var(name)`, `Lambda(param, body)`, `Apply(fn, arg)`, `If(cond, yes, no)`.

`def` is a top-level form rather than an expression. Inference retains Hindley–Milner polymorphism and purity. The v0.8 parser is *written in Nail* and returns an inert syntax tree as a value; execution remains the responsibility of the Haxe VM.

## Syntax, a typed value, not a sixth expression

The Nail value domain gains:

- `SyntaxLeaf(tag: Text, text: Text)`
- `SyntaxNode(tag: Text, children: [Syntax])`

The Haxe `NType` domain gains a single `Syntax` type. It is comparable by structural equality. The constructor and inspector primitives have these types:

```
syntaxLeaf     : Text -> Text -> Syntax
syntaxNode     : Text -> [Syntax] -> Syntax
syntaxTag      : Syntax -> Text
syntaxText     : Syntax -> Text     # leaf only
syntaxChildren : Syntax -> [Syntax] # node only
```

Invalid inspectors throw a runtime error. `Syntax` is serialized to an object of the shape `{tag, value}` for a leaf or `{tag, children}` for a node. Nested syntax nodes can have varying tags without losing homogeneous list types. No general-purpose `Any` or dynamic casts are exposed to Nail.

## Parser results

```
Program [ Define [ Name("twice"), Lambda [ Name("x"), Apply[...] ] ] ]
```

Canonical serialized form example:

```json
{"tag":"Program","children":[{"tag":"Evaluate","children":[{"tag":"Literal","children":[{"tag":"Number","value":"1"}]}]}]}
```

Functions parsing source are defined in `stdlib.nail`, including `parseAt`, `parsePrefix`, `parseSuffix`, `parseListItems`, `parseDefinition`, `parseForm`, `parseForms`, `parseSource`. This implements Pratt precedence parsing. Tokens and returned parse cursors are *homogeneous lists of Syntax*: a result is `[parsedTree, unconsumedToken1, ...]`, so no native parser-state class is needed. Parsing errors are returned as `SyntaxLeaf("Error", message)`; `parseSource` returns the first error instead of a partial program.

## Grammar subset

```
program    := (definition | expression ';')*
definition := 'def' identifier identifier* '=' expression ';'
expression := atom (atom | operator expression)*
atom       := number | identifier | 'true' | 'false' | '[]'
            | '(' expression ')'
            | '[' (expression (',' expression)*)? ']'
            | 'fun' identifier+ '->' expression
            | 'if' expression 'then' expression 'else' expression
            | 'let' identifier '=' expression 'in' expression
```

Application binds tighter than `* /`, which bind tighter than `+ -`, which bind tighter than comparisons and equality. All infix operators associate to the left. Numeric tokens are **kept as text** in `Literal/Number` nodes pending a later self-hosted numeric parser, avoiding host number conversion. `let`, list literals and infix operators are desugared into the five expression cases. List literals use the bootstrap-compatible reserved `#cons` primitive. `Syntax` children for Lambda contain a `Name` leaf followed by the body.

The current self-parser intentionally excludes `match`, text literals in the inner source, escaped strings, comments, automatic whitespace around punctuation and numeric exponent notation. The outer Haxe parser still supports the previous full language. These limitations must be removed before claiming full bootstrap equivalence.

## Portability contract

The original runtime and type-checker regression suites remain. The added `SelfParserTestMain` suite compares full serialized syntax trees to trees constructed from the existing Haxe `Parser.parse()` AST and checks errors on malformed input. GitHub Actions runs the same tests using `--interp`, compiled JS and compiled PHP. The suite checks what is implemented, not the entire language.

## Costs to measure

Pratt parsing in source Nail is deliberately simple but allocates many small immutable Syntax values and performs repeated textual identifier checks. Recursive depth, allocation and the default instruction step budget impose practical input-length limits. No security guarantees for untrusted input; do not expose VM execution to arbitrary remote source without stronger resource isolation.
