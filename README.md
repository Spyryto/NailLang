# NailLang

NailLang is an experimental programming language implemented in Haxe, with JavaScript and PHP runtime targets.

**Current development: v0.52** — typed synchronous `NailHost` functions now accept and return immutable, recursively typed Nail lists (including `CoreResult` payloads). Boundary checks reject malformed list tails, incorrect element types and excessive nesting/size; revocation and invocation budgets remain enforced. Mutable vectors and arbitrary foreign objects are deliberately excluded. The short `Ok` / `Error` constructors, source analysis, n-ary relations, and source-free JS/PHP runtime remain available. No new VM opcode or source syntax is required.

## Compatibility policy before 1.0

**No backward compatibility is guaranteed before NailLang 1.0.** Each release may change or remove syntax, source semantics, runtime behavior, standard-library interfaces, or compiled module/bootstrap ABIs whenever simplifying or improving the language warrants it. Changes must be documented in the release notes.

Historical versions remain accessible through Git tags, releases, and versioned documentation, together with their corresponding compiler/runtime artifacts. Running an old program with its historical toolchain is the reliable compatibility path.

Compatibility with older source versions or compiled modules may be retained **only when it provides concrete value at acceptable complexity**, not as an architectural commitment. We may delete old compatibility paths and historical regression expectations from the current compiler; historical tests belong to their respective tagged versions. An ABI version is a format identifier, not a promise of cross-version support.

The compatibility guarantees for 1.0 will be specified separately before that release.

This repository reconstructs the original NailSeed prototype as a clean, version-by-version public Git history. Each historic version has its own commit and tag. The current branch contains a single src/ directory, rather than numbered version folders.

- Language source and Haxe implementation: src/
- Language tour: LANGUAGE-TOUR.md
- Cookbook: COOKBOOK.md
- Dart-guided practical comparison: COOKBOOK-DART.md (including loops and recursion)
- Lookbook of missing or composable Dart features: LOOKBOOK.md
- Run from the command line or embed in JavaScript/PHP: RUNNING.md
- Historical language tours and code: docs/versions.md
- Downloadable historical source and compiled distributions: GitHub Releases (assets vary by release)
- Current Haxe/JS/PHP build and targeted test workflow: .github/workflows/ci.yml
- Tagged distributions (full VM and source-free boot): .github/workflows/release.yml
- Stage-zero seed vs Nail self-hosted stages, runtime boundary and verification: docs/BOOTSTRAP.md
- Editor-independent structured source analysis: docs/ANALYSIS.md

The v0.16, v0.28 and v0.29 numeric experiments are preserved under experiments/numeric in their historical tags. They are research experiments, not replacements for the main compiler. Python is not required for local builds and tests; 270 independent numeric reference cases are committed.

Source commits and tags were reconstructed using GitHub noreply authors. The private original commit history, Actions logs and any related private metadata have not been imported.

NailLang is experimental, not stable. No open-source license has been selected yet; public visibility alone is not a license for reuse or redistribution.
