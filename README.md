# NailSeed v0.26 — Source provenance and binding identities

Independent follow-up to [v0.25](../v0.25/), which remains unchanged.
The five-expression core, runtime semantics and canonical bytecode stay intact.

## Implemented in this experiment

- Token offsets and start/end coordinates with strings and comments.
- Optional `Parser.provenance` sidecar for expressions and top-level forms.
- Macro normalization preserving source argument spans and reporting the
  expansion call site separately.
- Iterative `BindingAnalysis.resolve(forms, parser.provenance)` producing
  deterministic per-program IDs for lambda parameters and definitions.
  Shadowing, self-reference and macro-global bypass are covered by tests.
- Interpreter, JavaScript and PHP provenance regression tests alongside the
  inherited cross-target bootstrap and runtime checks.

## Try it

```sh
haxe source-positions-test-interp.hxml
haxe source-positions-test-js.hxml && node build/tests/source-positions.js
haxe source-positions-test-php.hxml && php build/tests/php-source-positions/index.php
```

## Self-hosted source maps (implemented in Nail)

An optional Nail-written library, `source-provenance.nail`, provides two
inspectors. Load it **after** the ordinary standard library; it is deliberately
excluded from the canonical bootstrap image:

```nail
def source = " def x = 7 ; x ; " ;
tokenizeWithPositions source ;
parseSourceWithPositions source ;
```

`tokenizeWithPositions : Text -> [LocatedToken]` uses the Nail-written lexer
and a Nail-written position scanner; each record contains the unchanged
`Syntax` token plus a `SourceSpan` with half-open offsets and start/end
line/column. `parseSourceWithPositions : Text -> [LocatedForm]` calls the
real Nail `parseForm` for each form, matching consumed tokens to its original
source range. The canonical `parseSource` result remains unchanged.

The new `SelfSourceProvenanceTestMain` loads this library on demand, then
independently compares Nail-computed
token and form locations against the Haxe sidecar, including multiline input,
comments, strings, macros and source-free bootstrap execution on all targets.

The inspectable source map costs extra scanning/allocations and is not computed
or even loaded by ordinary compilation. To load the library through a Haxe
host, run `vm.run(sourceProvenanceNailText)` after `vm.loadStdlib()`;
`BootRuntime` can load the same Nail source with `runPlain` in its
source-free runtime.

## Deliberate limits

The Haxe sidecar tracks parsed expressions and outer macro call sites.
The **self-hosted Nail sidecar tracks tokens and complete top-level forms**,
but not each nested expression, synthesized lambda, or transformation-created
child. The Nail companion reports completed forms; call `parseSource` separately
to inspect parse errors. No metadata is inserted into the canonical
Syntax/bytecode image. Binding IDs are analysis-only, not yet a public
hygienic macro API. Generated declaration signature validation is the
next proposed version, v0.27.

See [../ROADMAP.md](../ROADMAP.md) for the numerical evaluation and the
balanced-language milestone.
