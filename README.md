# NailSeed v0.12 — Iterative bootstrap

This version removes host-language recursion from both the AST evaluator and structured-bytecode interpreter. Earlier versions are preserved unchanged.

The AST interpreter now uses a CEK-style loop with explicit application/branch continuations. The ByteVM has a single instruction loop: non-tail CALL and BRANCH save heap frames, while TAIL_CALL replaces the current activation. There are no new source constructs or opcodes; the five-expression AST and stdlib.nail are unchanged.

## Verification

From v0.12 with Haxe 4.3.7:

- haxe bootstrap-test-interp.hxml
- haxe bootstrap-test-js.hxml && node build/tests/bootstrap.js
- haxe bootstrap-test-php.hxml && php build/tests/php-bootstrap/index.php

The test exercises the Nail-written lexer/parser/compiler on a long input, 8,500 nested non-tail calls, 12,000 mutual tail calls, 1,700 compiled forms (including a bytecode-bootstrapped Nail compiler), and execution budgets. GitHub Actions also runs the historical runtime, typing, parser and compiler suites and creates JS/PHP distribution artifacts.

## Limits

This change eliminates host recursion **during evaluation of Nail function applications**. Some host bootstrap routines (Haxe Parser, SyntaxBridge, SyntaxEncoder and type inference) still traverse deeply nested *syntax trees* recursively. Non-tail recursion consumes managed-heap continuations; constant-space execution applies only to tail calls. No security sandbox or complete self-hosting is claimed.
