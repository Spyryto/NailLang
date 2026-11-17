# Editor-independent analysis API (NailLang 0.50 groundwork)

`nail.SourceAnalysis.analyze(source, ?modules)` inspects a Nail source
snapshot without running it. The full developer JavaScript distribution
exposes `NailSeed.analyze(source, modules?)`:

```js
const { NailSeed } = require('./build/js/nailseed.js');
const report = NailSeed.analyze('nail 0.50 ; def id x = x ; id 42 ;');
console.log(report.ok, report.symbols, report.evaluations, report.diagnostics);
```

The result fields are:
- `ok: Bool`: whether parsing, macro expansion and type checking succeeded
- `version: String?`: explicit `nail X.Y ;` header, otherwise null
- `diagnostics`: `{phase, message, span}` for parse/type failures
- `symbols`: `{id, name, kind, span, signature}` for ordinary definitions and parameters
- `references`: `{name, targetId, span}` for source variables
- `evaluations`: `{type, span}` for each top-level evaluation form

Spans are half-open `{start,end,line,column,endLine,endColumn}`, with
one-based lines and columns. Missing source locations are **null**, not
guessed. The parser can locate an expected token at EOF with a zero-width
span; type failures point to the enclosing original form. Lexical symbol
identities are scoped **only to one analysis result**, not persisted across
edits. A null reference target may denote a built-in primitive or an
unresolved name; static checking determines whether it is valid.

On a parse error, no partial symbols are returned. On a type error, the
report may retain lexical symbols and references but not invented types.
Only a fully successful analysis has inferred signatures and evaluation
types. No compiler bytecode or runtime state is mutated or executed.

The analyzer reuses **one** parser and macro-expanded form list for both
binding analysis and type inference, so imports are not fetched twice.
It is part of the **full** Haxe/JS/PHP developer distribution: the
source-free runtime intentionally excludes Haxe's parser/type checker.

This first API does not yet model nominal type/constructor symbol
namespaces, property names, per-expression inferred types, incremental
queries or Unicode-equivalent offsets across every backend. It does not
include an LSP transport, VS Code coupling, completion, hover or rename;
those are separate roadmap steps.

The cross-target regression suite is in
`source-analysis-test-interp.hxml`,
`source-analysis-test-js.hxml`,
`source-analysis-test-php.hxml`.
