# Versioning plan: compiler, language, bytecode

Dart's language versioning inspired this design: language semantics can be selected independently of the SDK/toolchain release, and a single compiler can support older language versions.

## Three version numbers, intentionally separate

| What | Example | Why |
| --- | --- | --- |
| **Compiler release** | `nailc 0.16.0-dev` | Bugs, optimization, diagnostic improvements; changes should not automatically alter language semantics |
| **Language dialect** | `# nail: 0.15` or `# nail: 0.16` | Freezes parsing and runtime language rules per source unit |
| **Bytecode format** | `bytecode: 1` | Loader rejects incompatible images; bytecode format can evolve separately |

Potential fourth version: standard library package version, managed explicitly if API compatibility requires it.

## Proposed comment header

```nail
# nail: 0.16

def half x = x * 1/2 ;
```

This uses the existing whitespace-tokenized, comment-capable style and requires no new lexical punctuation.

- The first nonempty line may contain `# nail: MAJOR.MINOR`.
- The **prototype** `LanguageVersion.detect` recognizes only `0.15` and `0.16`.
- For compatibility the prototype defaults an unmarked file to `0.15`.
- Unknown language versions are rejected explicitly instead of silently falling back.
- All of these are **design proposals**, not integrated compiler features.

## Why this matters for exact numbers

```nail
# nail: 0.15
1 / 3 ;   # old floating number semantics
```

```nail
# nail: 0.16
1 / 3 ;   # proposed exact rational semantics
```

A newer compiler could accept both, preserving the meaning of older code. **Mixing versions across modules** requires a well-defined interop policy, especially once `Number` changes semantics; deferring that integration is intentional.

## Bootstrap metadata

The source language version and **bytecode format version must not be conflated**. An image header should eventually include `format`, `dialect`, `stdlib`, and `compiler_build`, plus a content hash of the canonical image. The compiled bootstrap image can then be checked without pinning every user source file to the same compiler build.

A hash verifies image identity/integrity, not semantic correctness. Rebootstrap fixed-point tests from v0.15 remain valuable and independent.

References: https://dart.dev/language/versioning and https://dart.dev/tools/pub/pubspec
