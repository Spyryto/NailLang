# NailLang

NailLang is an experimental programming language implemented in Haxe, with JavaScript and PHP runtime targets.

**Current development: v0.41** — one-way revocation of read/write host capability instances and independently scoped module grants. Existing imports and partially applied writer functions honor revocation. v0.40 adds pinned SHA-256 module integrity; a hash is **not** a publisher signature. Release tags remain immutable.

This repository reconstructs the original NailSeed prototype as a clean, version-by-version public Git history. Each historic version has its own commit and tag. The current branch contains a single src/ directory, rather than numbered version folders.

- Language source and Haxe implementation: src/
- Language tour: LANGUAGE-TOUR.md
- Cookbook: COOKBOOK.md
- Run from the command line or embed in JavaScript/PHP: RUNNING.md
- Historical language tours and code: docs/versions.md
- Downloadable historical source and compiled distributions: GitHub Releases (assets vary by release)
- Current Haxe/JS/PHP build and targeted test workflow: .github/workflows/ci.yml
- Future tagged distribution workflow: .github/workflows/release.yml

The v0.16, v0.28 and v0.29 numeric experiments are preserved under experiments/numeric in their historical tags. They are research experiments, not replacements for the main compiler. Python is not required for local builds and tests; 270 independent numeric reference cases are committed.

Source commits and tags were reconstructed using GitHub noreply authors. The private original commit history, Actions logs and any related private metadata have not been imported.

NailLang is experimental, not stable. No open-source license has been selected yet; public visibility alone is not a license for reuse or redistribution.
