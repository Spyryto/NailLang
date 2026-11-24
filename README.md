# NailLang

NailLang is an experimental programming language implemented in Haxe, with JavaScript and PHP runtime targets.

**Latest public release:** [v0.60](https://github.com/Spyryto/NailLang/releases/tag/v0.60) · **Status:** experimental.

Nail favors a small, functional language core, explicit types and simple composition. It runs through the Haxe implementation on JavaScript and PHP; the standard builds are interpreters, **not** Nail-to-JS/PHP source transpilers.

## Quick start

This is a complete Nail program ([`examples/hello-060.nail`](examples/hello-060.nail)):

```nail
nail 0.60 ;
def answer = 42 ;
answer ;
```

From a checkout with Haxe 4.3.x and Node.js 22:

```sh
haxe seed-image.hxml
haxe js.hxml
node -e 'const fs=require("node:fs"); const {NailSeed}=require("./build/js/nailseed.js"); const vm=NailSeed.create(); vm.loadStdlib(); console.log(vm.runPlain(fs.readFileSync("examples/hello-060.nail","utf8")));'
```

Expected VM result: `["I:42/1"]` (a returned value, not an implicit print statement).

To run the same file with PHP 8, after generating the bootstrap image:

```sh
haxe php.hxml
php build/php/index.php examples/hello-060.nail
```

See [RUNNING.md](RUNNING.md) for browser use, source-free bundles and additional commands.

## Interoperability: use what already exists

Nail modules can **declare** a typed host function:

```nail
nail 0.60 ;
def hello name = greet name ;
import greet from NailHost : Text -> Text ;
```

The embedding Haxe application explicitly registers `greet`; no new FFI is needed. An import declaration alone does **not** authorize a host callback. The same Haxe example compiles and runs on Haxe, Node and PHP.

- [Runnable example and commands](RUNNING.md#060--primo-esempio-di-interoperabilità-con-lhost)
- [Nail source](examples/host-greeting-060.nail) · [Haxe host example](src/HostInteropQuickstartTestMain.hx)

*The interoperability quickstart was added to `main` after the v0.60 tag. It is available in the repository checkout, not in the original v0.60 release archives.*

## Compiler research (optional)

Version 0.60 also explores independently checked provider modules, a Nail-first type-checking path, Nail-written macro expansion and a five-constructor semantic CoreIR. These are experimental implementation paths, **not extra requirements for ordinary Nail programs**. See [v0.60 technical notes](docs/releases/0.60.md); the public module ABI remains unchanged.

## Project direction

- [Project principles (Italian)](PRINCIPLES.md): stable design and development guidelines.
- [Decision log (Italian)](DECISIONS.md): adopted, experimental and rejected choices, with rationale.
- [Roadmap (Italian)](ROADMAP.md): current release gates and proposed future directions.

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
- F# functional comparison and evolving feature lookbook: [COOKBOOK-FSHARP.md](COOKBOOK-FSHARP.md)
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

