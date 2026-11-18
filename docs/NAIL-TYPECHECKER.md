# Nail-written type checker — staged dogfooding experiment

**Status:** stacked experimental draft PR #29 (based on the contextual DSL
prototype in PR #28). Neither PR changes the released NailLang 0.54.

## Purpose

Implement the type checker *in Nail*, not via a host function which delegates
to the existing Haxe `TypeChecker`. Keep the Haxe implementation as an
independent reference until parity and diagnostics can be verified.

The first checker lives in `stdlib.nail`, with functions prefixed `tc`.
It is compiled to ordinary Nail bytecode during the normal bootstrap. The
existing VM and primitive boundary are unchanged.

## Representation

| Item | First-class Nail representation |
| --- | --- |
| Type variable | `syntaxLeaf "TCVar" id` |
| Primitive type | `syntaxLeaf "TCBase" name` |
| Function / list | `syntaxNode "TCFun"/"TCList"` |
| Closed structural record | `syntaxNode "TCStruct" fields` |
| Open structural requirement | `syntaxNode "TCRowField" [name, type, rest]` |
| Polymorphic scheme | `syntaxNode "TCScheme" [term, quantifiers]` |
| Substitutions / environments | Persistent association lists |
| Inference outcome | `Ok(TCChecked)` or `Error(Text)` |

Type variables are generated using a deterministic textual counter. The
algorithm is purely functional: substitutions and the next variable label
are returned through ordinary `Syntax` data rather than mutable VM state.
Unification performs an **occurs check** to reject infinite types.

## Present scope

- Full *five-case core expression* traversal: `Var`, `Literal`,
  `Lambda`, `Apply`, `If`
- Hindley–Milner unification, lexical environments, generalization of
  direct `let`, fresh instantiation, sequential recursive `def`
- Primitive `Int`, `Ratio`, `Number`, `Exact`, `Bool`, `Text`
  and type-variable lists
- Closed anonymous record fields and **limited open-row projection** of
  unknown record parameters, including width matching against known records
- A **conservative primitive prelude** for selected arithmetic/text/list
  operations; deliberately not a claim of full 0.54 typing semantics

### API

`tcCheckSyntax program` takes an already lowered `Program` Syntax node,
without parsing or invoking the Haxe checker.

`tcCheckSource source` is an experimental convenience helper which invokes
the **Nail-written** `parseSource`, then the existing `modernRewrite` and
`tcCheckSyntax`. It returns `Ok(TCChecked)` with a list of inferred
expression types, or `Error(Text)`. `tcPretty` formats an individual type.

The runtime does **not** automatically run `tcCheckSource` before
`compileSource`. Checking remains opt-in, so the incomplete checker cannot
silently reject or reinterpret supported programs.

## Parity and coverage gaps

The Haxe checker is used **only in differential tests**, not by the Nail
inferencer. See `src/NailTypecheckerProbeTestMain.hx`.

The following are not yet complete:

- Polymorphic numeric operator relations (`Div`, `Add`, ...), `Eq`
  constraints, general operator overloads
- Nominal record/sum declarations and complete structural row algebra:
  open-row **reordering**, row-lacks constraints and row-polymorphic ABI
- `type Html = {...}` alias verification and parameter annotations in the
  Nail-written checker; the Nail-written *parser* may erase annotations
  for execution, but this is not static checking
- Full standard-library primitive signatures, macro-aware typed expansion,
  import and module signatures, precise source-span diagnostics
- Performance and bounded-resource policies for adversarial/large terms

Unsupported cases must return a diagnostic rather than being accepted with
invented types. **The Haxe checker remains authoritative for public code.**

## Reproduce

From the root of the repository, with Haxe 4.3.x, Node and PHP installed:

```sh
haxe seed-image.hxml
haxe nail-typechecker-test-interp.hxml
haxe nail-typechecker-test-js.hxml
node build/tests/nail-typechecker.js
haxe nail-typechecker-test-php.hxml
php build/tests/php-nail-typechecker/index.php
```

The test suite includes successes and failures and compares outcomes with
the independent Haxe checker (using its explicit open-row opt-in when
relevant). It also validates that the Nail checker runs from its bytecode
image on Haxe, JavaScript and PHP.
