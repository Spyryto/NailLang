# Next DSL choices (design only)

## F# terminology

A `fun` expression is an anonymous function; `function | ...` is a function whose
argument is matched against patterns. Nail already has `fun` and `match`; combining
them syntactically is a small, independent surface feature.

F# computation expressions support sequenced computations using builder operations
such as Bind and Return. This is a promising model for a Nail Result/parser DSL,
with an initial translation into ordinary functions and lambdas. It does not
require runtime fexprs or full user-defined grammar support.

References:
- https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/computation-expressions
- https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/functions/lambda-expressions-the-fun-keyword

## Anonymous records as named arguments

Recommended first scope: immutable structural records with exact field sets,
order-independent type identity, duplicate/unknown field diagnostics, and normal
field projection. Field values should evaluate once in source order, even if type
identity canonicalizes field order. A single record argument is not curried named
parameters: partial application of individual fields would need a separate rule.

Do not silently add defaults, optional fields, width subtyping or row polymorphism.
Introduce these only if real DSL examples require them. A function accepting any
record with a `tempo` field is a larger inference feature than a function expecting
one exact anonymous record shape.

A lower-cost alternative is named construction of existing nominal records. It
can provide readable configuration calls while preserving today's nominal type
system. Anonymous records remain valuable for one-off option groups, but are a
separate type-system experiment, not part of the record transformer change.

Reference:
- https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/anonymous-records

## Recommended next experiment

1. Add source positions and binding identity to the syntax boundary.
2. Establish how generated declarations are checked against their signatures.
3. Add a small procedural-transformer interface and quotation helpers.
4. Try a Result/parser computation block using Bind and Return.
5. Test named record construction against anonymous records on one real lesson DSL.

The v0.25 extraction proves only the trusted record transformation stage. It does
not claim to implement this whole roadmap.
