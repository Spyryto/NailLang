# NailSeed v0.22 — Expression macro specification

## Syntax

- `macro name param ... = quote ( expression ) ;` defines an expression
  transformer with zero or more distinct parameters.
- `expand name arg ...` consumes the declared number of arguments, following
  ordinary curried application's precedence and grouping. Any remaining
  arguments apply to the resulting expression. Use parentheses for an argument
  containing application or an infix operator.
- `unquote param` is a hole in a template. Use parentheses when the hole
  itself is an argument, for example `f ( unquote param )`. It takes a
  parameter name, and can appear zero, one, or several times.
- As elsewhere in NailSeed, punctuation must be separated by whitespace.
  Quote groups follow ordinary expression parsing.
- The four new keywords are reserved: `macro`, `quote`, `unquote`, `expand`.

## Expansion

A unit is one source buffer or parsed program. Macro declarations are
visible in following forms of that unit and in their own template.
Nested calls from a template see only macro declarations available at the
definition site. Macro arguments are expanded in their original scope
before substitution. A macro declaration has no runtime value and macro
names occupy a separate namespace from ordinary definitions.

Each template lambda receives a fresh internal binding. Template-bound
occurrences use that binding and free template identifiers resolve in
the top-level value namespace, which has no same-name redefinitions.
Inserted argument trees keep the bindings of their original context.
A macro can duplicate an argument or omit it, so runtime evaluation
frequency depends on how the resulting tree uses each hole.

Both parsers produce marked expression trees. A shared Haxe expansion
pass handles them. The Nail-written compiler invokes that pass on
`Syntax` via `macroExpandSyntax`. The source-free runtime uses its
precompiled Nail parser and compiler and the same expansion primitive.
The result is ordinary expression code consumed by the optional checker
and both compilers. The VM resolves marked global references through
its global environment using its existing variable-load instruction.

Macro expansion has deterministic limits on nesting and work. Unknown
macros, missing arguments, invalid holes, duplicate declarations and
over-limit expansions fail at compile time. Optional checking sees
expanded record projections and algebraic matches, including coverage
errors.

The scope of this release is hygienic expression templates. Arbitrary
compile-time Nail functions, nested quotation levels, binding-name
splicing, and macro-generated top-level declarations have no syntax
in this version.
