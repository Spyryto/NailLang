# NailSeed v0.20 — An expression AST defined in Nail

The expression compiler now consumes **ordinary algebraic data types declared in Nail**. This advances [v0.19](../v0.19/) without changing the Haxe expression core, runtime values, or bytecode ISA.

```nail
type CoreLiteral = CoreNumber Text | CoreBoolean Text | CoreText Text | CoreNil ;
type CoreExpr = CoreLit CoreLiteral
  | CoreVar Text
  | CoreLambda Text CoreExpr
  | CoreApply CoreExpr CoreExpr
  | CoreIf CoreExpr CoreExpr CoreExpr ;
```

These declarations are part of `stdlib.nail`: they use the same nominal immutable records, generated constructors and exhaustive matching available to user programs. There is no new host `CoreExpr` value or primitive.

For example, after loading the standard library:

```nail
def identityAst = CoreLambda " x " ( CoreVar " x " ) ;
def answerAst = CoreApply identityAst ( CoreLit ( CoreNumber " 42 " ) ) ;
coreCompileTail answerAst ;
```

The resulting instruction list can be put in an existing bytecode program:

```nail
syntaxNode " Bytecode " [
  bcInstruction1 " EVAL " ( bcCode ( coreCompileTail answerAst ) )
] ;
```

Executing that bytecode with `ByteVm` returns `42`.

## The compiler boundary

`compileSource` retains its public behavior, but its expression compilation path is now:

1. The Nail parser produces the existing `Syntax` program and lowered expressions.
2. `coreRead` converts each expression to ordinary Nail ADT data.
3. `coreCompileGo` uses exhaustive constructor matching to emit the existing structured bytecode.

This is an actual compiler path change, not an unused parallel representation. Record and sum declarations still expand through the existing helpers, which also call the new expression compiler. `coreToSyntax` is a reverse adapter for tooling and roundtrip tests; the new compiler does not use it.

The optional Haxe checker verifies the entire standard library, including recursive `CoreExpr`, the adapters and compiler. Important inferred signatures:

```text
coreRead        : Syntax -> CoreRead
coreToSyntax    : CoreExpr -> Syntax
coreCompileGo   : CoreExpr -> Bool -> [Syntax]
CoreLambda      : Text -> CoreExpr -> CoreExpr
```

## Scope and compatibility

- Parser tokens, parser state, program forms, declarations and bytecode still use `Syntax`. This release migrates the expression IR and its compiler dispatch; it does not eliminate `Syntax`.
- Literal number and boolean spellings are stored as `Text` inside distinct literal constructors. This preserves the emitted bytecode exactly; it does not introduce exact rational arithmetic. Publicly constructed number literals are checked when the bytecode is decoded/executed, not by the ADT constructor.
- `coreRead` returns `CoreReadOk` or `CoreReadError` for unsupported tags, arities and boolean/nil spellings. Malformed leaf/node shapes are rejected by existing Syntax primitives. `compileGo` converts an adapter error to an invalid instruction that the VM rejects; it never silently omits that expression.
- `person . name`, internal `Person.name`, the five Haxe expression nodes and all opcodes are unchanged.
- Constructor/function names introduced here become standard-library names, as in prior globally named ADTs.
- No macros, new parser syntax, row polymorphism or parameterized recursive types are added.
- Existing parser limitations remain; in particular the Haxe parser's redundant-parenthesis shortcut does not handle every expression beginning with consecutive opening parentheses. A named intermediate value avoids that pre-existing limitation.

## Verification

The new 43-check suite covers inferred signatures, static rejection, recursively ordinary data, lossless expression roundtrips, exact bytecode agreement, malformed inputs, mixed record/sum programs, source-free operation and compilation of a 1,200-deep ADT.

```sh
haxe seed-image.hxml
haxe core-ast-test-interp.hxml
haxe core-ast-test-js.hxml && node build/tests/core-ast.js
haxe core-ast-test-php.hxml && php build/tests/php-core-ast/index.php
```

The v0.20 workflow also runs inherited regression suites and verifies Haxe → Nail → Nail bootstrap image equality. PHP's inherited regular rebootstrap test validates the Nail-generated image; a full PHP self-rebuild remains opt-in with `-D full_rebootstrap`.
