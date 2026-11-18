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
| Polymorphic scheme | `syntaxNode "TCScheme" [term, quantifiers, EqQuantifiers]` |
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
- **Optional parameter and value annotations**, structural type aliases
  `type Html = { h2 : Text Text , div : Text Text }`, required-field
  validation with allowance for additional implementation fields
- **Finite modern arithmetic**: direct binary `+`, `-`, `*`, `/`
  with concrete `Int`, `Ratio`, `Float` operand pairs and exact
  result domains; unresolved or mixed operands fail closed
- **Qualified polymorphic equality** `==` and `!=`: a free
  variable receives an `Eq` requirement, retained across unification,
  generalization, and fresh scheme instantiation. Primitive types,
  homogeneous lists and closed structural records are checked recursively;
  equality involving functions is rejected
- **Named finite relations of arity 1–16**, including `Add`, `Div`,
  `Merge : Text Text Text` and `Join3 : Text Text Text Text`. Each
  constrained function body is checked independently against **every**
  declared row, with input type constraints aligned to its exact parameter
  count. Fully applied calls select the output type from all input types.
  Duplicate tuples and inconsistent row arity are rejected
- A **conservative primitive prelude** for selected text/list operations;
  deliberately not a claim of full 0.54 typing semantics

### API

`tcCheckSyntax program` takes an already lowered `Program` Syntax node,
without parsing or invoking the Haxe checker.

`tcCheckSource source` is an experimental convenience helper which invokes
the **Nail-written** parser in a metadata-preserving mode,
`parseTypedForms`, followed by `modernRewrite` and `tcCheckSyntax`.
It retains `TypeAliasDecl`, `RelationDecl`, and `AnnotatedDefine`
only while checking; ordinary `parseSource` still erases them for execution.
The helper returns `Ok(TCChecked)` with a list of inferred expression
types, or `Error(Text)`. `tcPretty` formats an individual type.

The runtime does **not** automatically run `tcCheckSource` before
`compileSource`. Checking remains opt-in, so the incomplete checker cannot
silently reject or reinterpret supported programs.

## Example: explicit contracts and numeric relations

```nail
nail 0.54 ;
type Html = { h2 : Text Text , div : Text Text } ;
def render ( html : Html ) title = html { h2 title } ;
def page = { h2 = fun x -> x , div = fun x -> x , extra = true } ;
render page " Title " ;

Div : Int Int Ratio ;
Div : Float Float Float ;
def divide x y : Div = x / y ;
divide 6 3 ;
divide 6.0 3.0 ;
```

The checker accepts the extra `page.extra` field but rejects missing or
mistyped `h2` or `div`. A numeric relation is a finite set of statically
checked rows, **not** runtime overload dispatch. The receiver and the
overloaded function must have sufficient static information to resolve
their calls. The standard compiler still erases annotations before running
the program on the same VM.

For example, a three-parameter named relation is checked without any
special runtime support:

```nail
Join3 : Text Text Text Text ;
def join3 a b c : Join3 =
  textConcat ( textConcat a b ) c ;
join3 " A " " B " " C " ;
```

The checker handles one through sixteen parameter types (followed by
one result type), and checks arity, input tuple uniqueness and every
constrained definition. Partially applied or higher-order use of these
overloads is still deferred; such cases are rejected explicitly.

A concrete equality expression, such as `[ 1 , 2 ] == [ 1 , 3 ]`,
is checked to produce `Bool`. A polymorphic equality function can now
retain its required qualification, as illustrated by:

```nail
def same x y = x == y ;
same 3 3 ;
same " A " " B " ;
same [ 1 , 2 ] [ 1 , 3 ] ;
```

Each call instantiates a fresh `Eq`-qualified type variable. Unification
propagates the requirement to lists and structural fields; functions still
fail static checking. Internally the requirement lives in the same
persistent binding stream as substitutions (with a disjoint private key),
and the scheme preserves the quantified variables that are comparable.
The compiler does not perform runtime type-class dispatch.

## Parity and coverage gaps

The Haxe checker is used **only in differential tests**, not by the Nail
inferencer. See `src/NailTypecheckerProbeTestMain.hx`.

The following are not yet complete:

- Higher-order and partially applied overloaded numerical relations,
  nonconcrete numeric operand inference and explicit `Eq` syntax in
  user-authored signatures (inferred qualified schemes are implemented)
- Nominal record/sum declarations and complete structural row algebra:
  open-row **reordering**, row-lacks constraints and row-polymorphic ABI
- Generic/recursive structural aliases, applied nominal or `Node` types
  not yet available to the experimental checker
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
