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
