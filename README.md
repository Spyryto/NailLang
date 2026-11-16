# NailSeed v0.33 — inferred and polymorphic public interfaces (second slice)

This is an **independent v0.33 development snapshot** of v0.32.
The first slice removes duplicate monomorphic export types from host manifests;
the second adds an opt-in public scheme API for polymorphic imports/exports.

The new `ModuleLinker.compileInferred` accepts only export **names**,
reads their precise source types from the existing Hindley–Milner checker,
and creates canonical type signatures for the unchanged module-image ABI.
The existing `compile` API with explicit contracts remains supported.
Import signatures are still supplied explicitly and checked at link time.

## Example

```haxe
var image = ModuleImage.encode(ModuleLinker.compileInferred({
  name:'Core',
  source:'def double n = n + n ; def identity x = x ;',
  imports:[],
  exports:['double']       // no repeated Number -> Number signature!
}));
```

The compiler verifies `double` is an actual local definition,
infers `Number -> Number`, checks both compiler implementations agree,
and exposes only that public name. `identity` remains private.

`closedPublicType` refuses unresolved type variables, polymorphic
schemes, and nominal types; it never silently specializes such a value.
The tests include cross-module calls, rejection of private imports,
exact-number dialects, unknown/duplicate exports and nominal errors.

Run the new Haxe/JS/PHP tests after `haxe seed-image.hxml`:

```sh
haxe public-interfaces-test-interp.hxml
haxe public-interfaces-test-js.hxml && node build/tests/public-interfaces.js
haxe public-interfaces-test-php.hxml && php build/tests/php-public-interfaces/index.php
```

The CI also runs the entire inherited v0.32 suite.

## Remaining v0.33 goals

- Public **nominal type identity** across module boundaries, including
  constructor ownership and canonical wire representation.
- **Machine-readable portable HM schemes** in compiled module images;
  the second slice checks them but serializes only canonical ABI text.
- **Generic nominal records** and optional source-level type annotations,
  with parity across the reference and Nail-written compilers.

These remaining features are **not** claimed here. Cross-module nominal
restrictions remain in force.

## Second slice: checked polymorphic interfaces

The opt-in `ModuleLinker.compilePublic` accepts full Hindley–Milner
`TypeScheme` contracts on imports, **rebinds quantified IDs** when imported
and infers export schemes from Nail code. The public ABI is still the
canonical signature string in `runtime-module.v1`: no new VM instructions,
no changes to the five expression forms or to the bootstrap compiler.

```haxe
var checker = new TypeChecker();
checker.check('def identity x = x ;');
var publicIdentity = checker.publicScheme('identity');
// The consumer can import this explicitly-quantified contract.
var module = ModuleLinker.compilePublic({
  name:'Example',
  source:'def run n = foreign_identity n ;',
  imports:[{module:'Core', symbol:'identity', alias:'foreign_identity',
    scheme:publicIdentity}],
  exports:['run']
});
```

Universal quantifiers must cover **all** type variables; every Eq
constraint must bind an existing quantifier; nominal types are rejected.
Each identifier occurrence is independently instantiated, so an imported
`a -> a` may be used at multiple concrete types. Link-time exact signature
comparison rejects weakened or forged contracts. Haxe, JavaScript and PHP
test the same behavior with source-free parity.

This slice does not yet serialize structured schemes in module images
(images store the canonical text ABI), provide cross-module nominal type
identity, or implement generic records / source annotations. The existing
`compile` and `compileInferred` APIs remain backward compatible.

## Third slice: opaque cross-module nominal records

`compilePublic` now accepts record declarations only when their type name
has the explicit provider prefix: `type People_Person { name Text age Number } ;`
in module `People`. For this interim wire convention, record-owning module
names must start with an uppercase letter and contain only letters/digits
(no underscores), so splitting the nominal identity is unambiguous. This makes `People_Person` and `Calendar_Person`
distinct even if their fields are identical. The existing `Value.Record`
runtime tag is that same qualified identity; no new runtime instruction
or bytecode format is introduced. Record constructors and ordinary helper
definitions can be exported; generated `Type.field` getters remain
private internal definitions.

A consumer imports the provider's inferred `TypeScheme` for public
constructor/helper functions. A qualified opaque record type can be
passed between separately compiled modules, and mismatched provider
ownership is rejected before linking. Importing a record does **not**
expose its field layout: a consumer uses explicitly exported helper
functions, rather than `person . field`. Nominal identity is **not**
structural equality.

This is an opt-in, deliberately restricted identity convention, not yet
the ergonomic source-native `module People; type Person` syntax.
Cross-module sums, generic nominal records, import of opaque record
field metadata and nominal re-exports through third-party modules
are still future work. The legacy monomorphic module compiler keeps its
existing restrictions.

## Fourth slice: parametric nominal records

The syntax `type Box a { value a } ;` and
`type Pair a b { first a second b } ;` is understood by **both**
the Haxe and Nail-written parsers. Nominal constructors and field accessors
are polymorphic: `Box : a -> Box[a]`, `Box.value : Box[a] -> a`.
Ordinary `box . value` projection infers the applied type; different
instantiations cannot be mixed accidentally. Static equality checks carry
any relevant `Eq` constraints through generic arguments.

The opt-in public module API supports provider-qualified generic records
like `Store_Box[a]`. The module's Haxe `TypeScheme` exposes the same
generics to separately compiled consumers, which use explicitly exported
functions to manipulate opaque records. Link-time canonical signatures
still protect compatibility. Runtime record tags retain a stable
`Store_Box` owner name; type arguments are enforced by HM checking rather
than stored as new bytecode instructions.

**Boundaries:** field declarations are atomic types or declared type
parameters, not nested applications (`List a`, `Box (List a)`) or recursive
generic records. This slice does not add source-native runtime imports,
exported record layouts, quantified structured image metadata or generic
cross-module sum type ownership. The original monomorphic record syntax
remains supported.

## Named-field record construction (v0.34 first slice)

Write `Person { age = 36 , name = " Ada " }` instead of relying on
positional argument order. Both parsers emit existing `#recordMake`,
`#cons`, `Literal`, `Apply` nodes: no sixth expression kind or new VM
opcode. Fields are evaluated **once, left to right in source order**, and
stored by their names; declaration order can differ. The type checker
uses the existing nominal constructor and qualified getter schemes to
check each field independently, including `Box a` and `Pair a b`.

Named construction requires all declared fields, rejects unknown and
duplicate fields and respects the established record identity and
numeric dialect. Commas separate named assignments. In untyped VM
execution, as with other unchecked raw source, static type errors are
only rejected when the caller invokes `TypeChecker`; use the typed path
when schema validation is required.

## v0.35 first slice — anonymous closed structural records

Write `{ age = 36 , name = " Ada " }` without declaring a nominal
record type first. The checker infers a **closed** structural row:
`{age: Number, name: Text}`. Field order is canonicalized by name in
the type system, while **evaluation occurs once, in the written order**.
Field projection `profile . age` and equality work using the existing
`#recordMake` and `#recordGet` primitives and VM representation.
These records use the reserved `#struct` runtime identity, which is
disjoint from nominal types, even when field shapes happen to match.

There is no row polymorphism or width subtyping yet: `{x:Number}` and
`{x:Number,y:Bool}` are intentionally different types. Ordinary HM
quantification inside a structural field works; fully typed structural
schemes can cross separately compiled module boundaries without source
recompilation or a new module image schema. Canonical public signatures
remain text in image v1, with explicit contract checking at linking.

The five expression forms, bytecode instruction set, default Float and
opt-in Exact number semantics are unchanged. The empty form `{}` is
not supported yet, and anonymous fields must be explicitly named.
