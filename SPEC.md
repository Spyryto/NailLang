# NailSeed v0.19 — Self-hosted algebraic syntax and static coverage

## Data model

Surface `type Option a = None | Some a ;` produces the first-class `SumType` program form encoded as `SyntaxNode("SumType", [Name, Params, Constructors])`. Both host and Nail parsers generate this exact tree. Constructors are nominal, curried, and remain tagged immutable records with `#tag` and `#0` etc. The host bytecode compiler and Nail source compiler each desugar the type into matching `DEFINE` instructions. No new expression constructor or bytecode opcode is added.

## Constructor matching

`match value with | None -> zero | Some x -> x` compiles into `Apply(Lambda("#nail_sum_subject_0", nested If of discriminators), value)`. Hidden names are private, unique in lexical scope. Match branches bind constructor payloads through `Ctor.<n>` accessors. Unmatched alternatives use the private `#sumFail` primitive in untyped execution.

## Static validation

The optional Haxe Hindley–Milner inference performs an iterative scan of desugared expression trees. When it encounters the private sum-match lambda it identifies each `Ctor?` predicate and the corresponding `Ctor.0` etc. It requires:

1. At least one valid branch and all branches from the same nominal sum type.
2. Every constructor belonging to that sum type to occur exactly once.
3. Exactly as many positional binding variables as the constructor payload requires.

It reports missing constructor names and wrong arity before the usual type inference. Constructor registries are transactional within `TypeChecker.check` and carried across successful incremental calls. The checker does not implement row polymorphism or general GADTs.

## Preserved interfaces

- Runtime still executes Haxe/JS/PHP through the same Haxe codebase.
- SyntaxBridge remains a validated conversion between typed `Syntax` values and the five-form core AST.
- Public record syntax `record . field` and internal getters `Type.field` are unchanged.
- The experimental exact-rational code from v0.16 is not merged.
