# NailSeed 0.7 — text semantics & self-hosting milestone

## Core invariants

The complete expression AST remains `Literal | Var | Lambda | Apply | If` and all library code uses these forms after desugaring. The runtime evaluator in Haxe compiles to JS and PHP.

## Strings

Source form: `" content with words "` where both quote marks are separate whitespace tokens. Raw whitespace between string payload words is normalized to one space. Quotes inside strings require the JSON escape `\"`, and escapes `\n`, `\t`, `\r`, `\uXXXX` are decoded with the Haxe JSON parser. An empty string is `" "`. A string containing one space is `" \u0020 "`.

All real strings are represented at runtime as `Text(String)` and statically as `TText`. Equality between text values is by contents; `Text` is an `Eq` type, and `[Text]` can be compared structurally. Comparisons across types remain statically invalid.

Minimal host APIs:

- `textLength : Text -> Number`
- `textAt : Text -> Number -> Text` (zero-based, integer-only, bounds checked)
- `textConcat : Text -> Text -> Text`

Indexable text is ASCII only (U+0000–U+007F) until portable Unicode scalar semantics can be specified. `textLength` and `textAt` reject non-ASCII input rather than silently disagreeing between target hosts.

## First Nail-native tooling

`tokenize : Text -> [Text]` scans a string in Nail, recognizing space, tab, CR and LF and returning whitespace-separated tokens. All helper functions are written in `stdlib.nail`; there is no host `split` primitive. 

`parseTinyDef : Text -> [Text]` recognizes one special-case grammar: `def NAME ARG = ARG +|* LITERAL ;`. It returns a flat prefix-AST token sequence. It rejects unexpected token counts, mismatch between body variable and argument, unrecognized operators, etc. Its implementation is intentionally unsophisticated; this is a vertical slice proving that Nail can tokenize and inspect a subset of its own syntax, **not** full self-hosting.

## Constraints and tests

The persistent-list representation from v0.6 is unchanged. Source `let` and exhaustive list `match` desugar to the same five AST nodes. `cases.json` and `type-cases.json` extend regression suites. The CI runs on Haxe --interp, Node and PHP, then tests the distribution API. No generated targets are versioned.

## Next work

A proper parser should return a tagged AST as algebraic data types instead of a flat `[Text]`, support errors with positions and work on full function syntax. Tail-call elimination or iterative tokenization may be required for larger inputs. Unicode semantics and a more robust string/tokenizer contract should precede any claims of self-hosting.
