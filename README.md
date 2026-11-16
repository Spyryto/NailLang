# NailSeed v0.7 — Text + self-hosted tokenizer and tiny parser

**Haxe-first**: single source for `--interp`, JavaScript and PHP. Same five core AST nodes as v0.6.

## New features

- A first-class `Text` value, `TText` type and text equality.
- Three host primitives only: `textLength`, `textAt`, `textConcat`. Characters processed by these primitives must be **ASCII** for identical JS/PHP indexing semantics in this experimental version.
- Text syntax: a double-quote delimiter must itself be a whitespace-separated token: `" hello world "`, `" "` (empty), `" \u0020 "` (single space); escape sequences inside quotes follow JSON rules. Content spacing is normalized to one space between constituent words.
- `tokenize`, `isSpace`, `tokenizeAt` implemented **in Nail**, not in Haxe; recursive and naïve but sufficient for small examples.
- `parseTinyDef` recognizes the narrow grammar `def NAME ARG = ARG OP LITERAL ;` for `+` and `*`; returns a flat prefix-AST represented as `[Text]`, or `[]` if unrecognized. This is not the production Nail parser or a self-hosted compiler.
- Existing v0.6 runtime and type tests preserved; new positive/negative tests validate text, tokens, simple source syntax and type errors.

## Example

```nail
tokenize " def twice x = x * 2 ; " ;
# ["def", "twice", "x", "=", "x", "*", "2", ";"]

parseTinyDef " def twice x = x * 2 ; " ;
# ["Define", "twice", "x", "Multiply", "x", "2"]
```

`stdlib.nail` contains all the new Nail-language functions. Load it once before calling them. The host parser itself is still written in Haxe and is responsible for bootstrapping the text library.

## Run

From this directory, with Haxe 4.3.7 installed:

```sh
haxe test-interp.hxml
haxe type-test-interp.hxml
haxe test-js.hxml && node build/tests/test.js
haxe type-test-js.hxml && node build/tests/types.js
haxe test-php.hxml && php build/tests/php/index.php
haxe type-test-php.hxml && php build/tests/php-types/index.php
```

Workflow: [nailseed-v07.yml](../.github/workflows/nailseed-v07.yml). Build artifacts are published by GitHub Actions, not committed.

## Limitations

- No full Nail parser in Nail itself, only a bounded grammar recognizer for one form.
- Source text is ASCII for indexing; text literals may contain other Unicode, but `textLength`/`textAt` reject it. Unicode/code-point semantics remain future work.
- The string delimiter and punctuation still require surrounding whitespace. String input normalizes the spaces between words; use JSON escapes (such as `\u0020`, `\t`, `\n`) to represent exact whitespace.
- No tail-call optimization. The tokenizer is recursive and intended for short source snippets, not arbitrary-sized input.
- Type checking remains optional in the execution API.
