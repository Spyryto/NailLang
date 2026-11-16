# NailSeed v0.22 — Hygienic expression macros

Declare a macro with a quoted expression and call it explicitly with
`expand`. Each `unquote` inserts an argument as an expression tree.

```nail
macro unless condition action = quote (
  if unquote condition then 0 else unquote action
) ;

expand unless false ( 40 + 2 ) ;   # 42
expand unless true ( 1 / 0 ) ;     # 0
```

Macros can introduce local bindings without capturing the caller's names.

```nail
macro addTen x = quote ( let tmp = 10 in tmp + unquote x ) ;
let tmp = 32 in expand addTen tmp ;   # 42
```

A macro template's free expression names resolve at the top level.
A caller's local binding with the same name has no effect on them.
An unquoted argument keeps its caller bindings. Expansion runs before
optional type inference and bytecode generation in both compiler paths,
including the runtime initialized from a bootstrap image.

`quote` and `unquote` are expression templates, with `unquote` accepting
a macro parameter. Macros are scoped to a compilation unit and can compose
with macro definitions visible at the declaration site. See [SPEC.md](SPEC.md)
for the grammar, scoping and limits.
