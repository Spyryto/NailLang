# NailSeed v0.27 — Generated record declaration contracts

This is an independent experimental snapshot based on
[v0.26](../v0.26/), which remains unchanged. It introduces an **opt-in
validation gate** for the trusted record transformer written in Nail.

## Validation contract

`GeneratedDeclarationValidator.validate(plan)` accepts the
`RecordExpansion` value emitted by the Nail transformer and:

1. Checks the original, un-erased source Program with `TypeChecker`,
   including nominal field signatures and ordinary expressions.
2. Independently lowers each `RecordType` to the constructor and qualified
   accessors using the Haxe `RecordLowering` reference implementation.
3. Compares every emitted definition and unchanged form against the expected
   **full** Syntax structure, rejecting missing, extra, renamed or modified
   definitions. It does not trust the generated names or arity alone.
4. Returns the unchanged runtime Program only when all checks pass.

The optional VM API is:

```haxe
var vm = new nail.Vm(50000000);
vm.loadStdlib();
var program = vm.validatedRecordsWithNail(source);
var bytecode = vm.compileValidatedWithNail(source);
```

The existing `compileWithNail` API and source-free `BootRuntime` remain
compatible; these new host-side entry points **do not silently change**
their behavior or introduce any new VM instruction.

## Reusable generated-definition signatures

The same release also exposes an independent, general contract for
**new generated definitions with closed, monomorphic signatures**:

```haxe
var original:Value = SyntaxEncoder.program(new Parser(
  "type Person { age Number } ;").parseRaw());
var generated:Value = SyntaxEncoder.program(new Parser(
  "def age person = person . age ;").parseRaw());

var signatures = [{name:"age",
  type:TFunction(TRecord("Person"), TNumber)}];

new TypeChecker().checkGenerated(original, generated, signatures);
GeneratedDeclarationValidator.validateTyped(original, generated, signatures);
var bytecode = vm.compileCheckedGenerated(original, generated, signatures);
```

This checks each emitted definition in order, rejects unexpected/duplicate
names and forms, validates known nominal types, and unifies each body with its
declared signature. Earlier definitions and original checked source bindings
may be referenced; the currently checked name can recurse. The checker works
transactionally and does not modify the caller's type environment.

The original and generated programs must be validated Syntax trees. Type
contracts use the host-side `NType` constructors: no type-annotation syntax
or user-defined procedural macro registration is implied. The optional
`callSite:SourceSpan` parameter on `validateTyped` enriches diagnostic
errors with source line/column without changing successful output.

**Polymorphic generated signatures are deliberately refused** until we have
sound skolemization/rigidity checks. This does not grant privileges to
generated code or introduce any new runtime operations.

## Validation

```sh
haxe seed-image.hxml
haxe generated-contract-test-interp.hxml
haxe generated-contract-test-js.hxml && node build/tests/generated-contract.js
haxe generated-contract-test-php.hxml && php build/tests/php-generated-contract/index.php
```

`GeneratedDeclarationValidationTestMain` checks nested/multiple and 128-field
records, absence of records, imported expression macros, missing/extra/changed
generated forms, nominal type errors, deterministic bytecode and execution
parity. The `nailseed-v027.yml` workflow repeats these tests across the
three targets and runs inherited bootstrap/fixed-point suites.

## Important boundaries

Two validation paths now coexist: (1) the trusted record-transformer
contract using exact equivalence to independent lowering, and (2) generic
type checking of new generated definitions when the host supplies explicit
**monomorphic** type contracts. Neither exposes public user-defined
procedural transformers, arbitrary unannotated inference of generated
declarations, or sound checking of polymorphic promised signatures.

The source-free bootstrap currently uses its existing trusted transformer
without invoking the optional host-side validator. Generated child-expression
provenance, richer source diagnostics and parametric type contract checking
remain later milestones.

See [../ROADMAP.md](../ROADMAP.md), including the v0.28–0.29 numeric work.
