# NailSeed v0.17.1 — Projection syntax

`receiver . identifier` is an explicit, postfix record field selection. Whitespace delimits all tokens (including `.`). It is left-associative and has precedence **80**, higher than ordinary application (**70**) or arithmetic operators.

Lowering (both parsers):

```text
p . age
=> Apply(Apply(Var("#recordGet"), Var("p")), Literal(Text("age")))
```

`#recordGet` already exists in v0.17 as a private two-argument primitive; thus no new VM instruction or core AST expression is needed.

The Hindley–Milner checker recognizes this lowered expression directly. It consults the nominal receiver type and the generated `Type_field` signature. If an unknown receiver type is involved, a field unique to one declared record may determine its nominal type. Shared fields are ambiguous without a known receiver type; no row polymorphism is implied. Projection on a non-record or absent field is a static error; the runtime also reports access errors.

Example: `( Person " Ada " 32 ) . age ;` has type `Number`. `def getAge x = x . age ;` has type `Person -> Number` if `age` occurs only in `Person`. `Person_age x` remains supported.

The bytecode compiler, SyntaxBridge, and self-hosted compiler retain their existing instruction set. CI verifies equivalent bytecode from both parser/compiler paths and successful execution on Haxe, JavaScript and PHP.