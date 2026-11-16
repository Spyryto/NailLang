# v0.27 delta: checked record-generation contract (opt-in)

`GeneratedDeclarationValidator.validate` accepts only a well-formed
`RecordExpansion [sourceProgram, runtimeProgram]`. It first type-checks
`sourceProgram`, then independently reconstructs the expected constructor
and getter definitions through the Haxe reference `RecordLowering`.
Every generated form and every preserved source form must be structurally
identical to the expected result; extra/missing/modified declarations fail.
On success, it returns `runtimeProgram` unchanged.

`Vm.validatedRecordsWithNail` and `Vm.compileValidatedWithNail` expose
this trusted, explicit validation path. Regular compilation and source-free
bootstrap remain unchanged. This exact-lowering record contract is separate from the host-side generic
monomorphic generated-definition checker below; neither exposes a public
procedural-macro registration API.

## Generic typed generated definitions (host-side)

`TypeChecker.checkGenerated(sourceSyntax, generatedSyntax, contracts)` is a
transactional type-checking entry point for a generated Program consisting
**only of fresh definitions** in the same order as a manifest of
`{name:String, type:NType}` contracts. Source syntax is checked first and
provides nominal types and earlier source bindings. Each generated
definition is inferred against its **closed, monomorphic** signature;
earlier generated names and the current recursive binding are in scope.
Unbound names, mismatched types, invalid nominal types, missing/extra
definitions, duplicate names and unsupported polymorphic contracts fail.

`GeneratedDeclarationValidator.validateTyped` accepts the same inputs
and returns the unchanged generated Syntax on success. Its optional
`SourceSpan` argument adds call-site line and column to errors.
`Vm.compileCheckedGenerated` compiles validated output through the normal
self-hosted Nail compiler. There is no new bytecode instruction or syntax
form. This is not a public arbitrary procedural macro system, and it
does not promise sound checking of polymorphic generated signatures.

---

# v0.26: Optional source maps and lexical binding identities

The host parser exposes token coordinates and external AST/source mapping.
A separate analysis resolves lexical references to stable per-program IDs.
Macro-expanded forms preserve original arguments and outer call-site ranges.
No change to the expression AST, runtime data model, or bootstrap bytecode.
Self-hosted parser spans, provenance for every generated child expression and
declaration signature validation remain out of scope.

---

# v0.25 delta: record declaration expansion

`expandRecordDeclarations : Syntax -> Syntax` maps a parser-validated Program to
`RecordExpansion [sourceProgram, runtimeProgram]`. Non-Program input is returned
unchanged, including parser errors. `recordExpansionSource` and
`recordExpansionRuntime` project the two Programs. They require a valid expansion.

`recordDefinitions : Syntax -> [Syntax]` takes a RecordType and produces constructor
and accessor Define forms, in declaration order. `compileSyntax` performs this pass
after expression macro expansion. The core AST, nominal record types, bytecode and
record primitives are unchanged. The transformer is trusted compiler code, not an
extension point for arbitrary user macros. Original syntax is retained without new
source-position or binding metadata. See README.md for API boundaries.

---

# NailSeed v0.24 — Macro modules

Macro expansion still follows the [0.22 template rules](../v0.22/SPEC.md).
This release adds two top-level directives.

```nail
import macroName from moduleName ;
export macroName ;
```

- Module names are identifiers. The resolver maps an identifier to source
  text. PHP's `--macro-dir DIR` option maps it to `DIR/moduleName.nail`.
  The resolver is explicit. There is no automatic working-directory lookup.
- A macro module contains macro declarations, imports, and exports. An export
  names a local macro already declared. Other macros are private. Runtime
  declarations and re-exports are rejected.
- Imports are ordered. An imported macro keeps the macro scope it had at
  declaration, including private macros and imports. The consumer's lexical
  bindings do not affect generated binders or free global references.
- Runtime names referenced by a template must be available in the consumer's
  global environment. Import only brings in macro definitions.
- Resolution is cached for a compilation and rejects cycles, missing modules,
  unavailable exports and duplicate imports. The same resolver can serve a
  host parser, the Nail parser and the bytecode-only bootstrap. Directives
  are removed before checking or bytecode generation.

The standard JavaScript API takes the optional resolver as its second argument
to `expand`, `runPlain`, `runPlainWithNail`, `check`, and `preview`.
The bootstrap runtime accepts it on `compile`, `run`, and `runPlain`.
The PHP bootstrap CLI also accepts `--macro-dir DIR`.
