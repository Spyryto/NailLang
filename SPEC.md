# NailSeed 0.2 — Functional source syntax (experimental)

## Design decision

Named parameters and ordinary functional expressions are the **only** user-facing model. There are no `dup`, `swap`, `rot`, or implicit stack effects to reason about. A stack may still implement an internal VM, but it is not a part of the language semantics.

This is a proof-of-concept language and not a finished replacement for NailVM 0.1. The 0.2 prototypes directly evaluate an AST rather than compile to 0.1 bytecode.

## Token rule

**Every token must be whitespace-delimited**, including punctuation:

    def twice x = x * 2 ;
    twice ( 5 + 1 ) ;

In this version, `twice(5+1);` is deliberately invalid. The tokenizer is essentially `source.trim().split(/\s+/)` after stripping standalone `#` line comments. Each definition/expression is terminated by `;`; a newline alone does not end a definition. Strings with spaces are temporarily written as URI-encoded `s:Ciao%20mondo` (to be redesigned).

## Surface examples

    def twice x = x * 2 ;
    def twice2 = * 2 ;         # operator section (shorthand)
    def square x = x * x ;

    def add a b = a + b ;
    def add3 = add 3 ;         # partial application

    def factorial n =
      if n < 2 then 1 else n * factorial ( n - 1 ) ;

    def makeAdder x = fun y -> x + y ;
    def add10 = makeAdder 10 ;

    map square [ 1 , 2 , 3 ] ;
    fold ( fun acc x -> acc + x ) 0 [ 1 , 2 , 3 ] ;
    [ 1 , 2 , 3 ] |> map twice ;

The section `* 2` means `fun x -> x * 2`. This convention also makes `/ 2` mean `fun x -> x / 2`. In particular it is **not** ordinary left currying of the binary operator: the surface syntax intentionally binds the implicit argument on the **left**. Named arguments remain canonical and are less surprising for noncommutative operators.

## Grammar sketch

    program      = (definition | expression ';')*
    definition   = 'def' name name* '=' expression ';'
    expression   = atom (application-argument | infix-op expression)*
    atom         = number | boolean | encoded-string | name
                 | '(' expression ')'
                 | '[' (expression (',' expression)*)? ']'
                 | 'fun' name+ '->' expression
                 | 'if' expression 'then' expression 'else' expression
                 | binary-operator atom

The actual parser uses precedence climbing (Pratt-like), with function application > multiplication/division > addition/subtraction > comparison > pipeline. `|>` is left associative; ordinary operators are left associative. Explicit parentheses are separate tokens.

## Runtime prototype

- Pure first-class functions, closure capture, single-argument currying, recursive global definitions.
- Host `map`, `filter`, `fold`; immutable list values in JS.
- Small arithmetic/comparison vocabulary and `if then else`.
- No `dup`, `rot`, `swap` or other stack operations in source code.
- Runs under Node.js and PHP 8. JS code targets Scriptable too, but was only tested in Node.js.
- 15 identical smoke tests passed in Node.js and PHP 8 in the authoring environment.
- Has a simple step budget but is **not** hardened to run arbitrary untrusted programs.

## Unimplemented / intentionally postponed

- Static type inference, user-defined algebraic data types and pattern matching.
- Module system and error spans.
- Natural quoted strings, Unicode syntax, tail-call optimization.
- Effect handling; PHP persistent immutable data representation.
- Compilation of source AST to the earlier NailVM bytecode.
- A self-hosting parser/compiler written in Nail itself.

## Architectural direction

    source language (named parameters, pure expressions)
        -> whitespace tokens
        -> tiny precedence parser
        -> small lambda/closure-based core AST
        -> [next] NailVM 0.1 compatible bytecode compiler
        -> JavaScript / PHP runtimes

Keep syntax sugar (`def`, `if`, infix operators, `|>`, operator sections) out of the semantic core. Core operations need only literals, variable lookup, lambda/closure, application, conditional and selected primitives; lexical environments hide all internal stack bookkeeping. This deliberately exchanges the absolute minimal grammar of Forth for an ordinary expression language with far lower cognitive burden for the author.