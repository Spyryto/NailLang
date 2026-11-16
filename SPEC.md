# NailSeed v0.20 — ordinary algebraic expression IR

## Data model

`CoreLiteral` has four constructors: `CoreNumber Text`, `CoreBoolean Text`, `CoreText Text`, and `CoreNil`. The textual payload retains the source representation used by Syntax bytecode. `CoreExpr` has exactly five constructors: `CoreLit CoreLiteral`, `CoreVar Text`, `CoreLambda Text CoreExpr`, `CoreApply CoreExpr CoreExpr`, and `CoreIf CoreExpr CoreExpr CoreExpr`.

All declarations and operations are written in `stdlib.nail`. Values are ordinary nominal ADT records, not special host Syntax values. Recursion is monomorphic and uses the existing v0.19 type rules. The compiler and adapters are checked by the existing optional Hindley–Milner checker.

## Conversion

`coreRead : Syntax -> CoreRead` consumes one lowered expression, not a Program. `CoreRead = CoreReadOk CoreExpr | CoreReadError Text`. It recognizes Literal/Var/Lambda/Apply/If, validates node arities, Lambda name tags, literal tags and boolean/nil spellings, and propagates nested conversion errors. Incorrect Syntax node/leaf shapes throw through existing primitive checks. Number spelling validity remains a responsibility of the existing literal decoder.

`coreToSyntax : CoreExpr -> Syntax` is a tooling adapter. For parser-produced expressions, converting to CoreExpr and back preserves the canonical Syntax tape. The compiler does not call this reverse adapter.

## Compilation

`coreCompileGo : CoreExpr -> Bool -> [Syntax]` is an exhaustive constructor match. A true second argument means tail position.

- Literal: CONST; RETURN in tail position.
- Variable: LOAD; RETURN in tail position.
- Lambda: CLOSURE with body compiled in tail position; RETURN if needed.
- Application: function then argument in non-tail position, followed by CALL or TAIL_CALL.
- Conditional: condition in non-tail position, followed by BRANCH whose arms inherit the current tail flag.

`coreCompileExpr` and `coreCompileTail` select the flag. Existing `compileGo`, `compileExpr`, `compileTail`, `compileSyntax` and `compileSource` APIs retain Syntax inputs. `compileGo` invokes coreRead then coreCompileGo; a conversion error emits an Error leaf which the bytecode executor rejects as an invalid instruction.

## Boundaries

No Haxe VM/core changes and no new opcodes. Parser state, forms, declarations and emitted bytecode retain Syntax. The independent Haxe compiler remains the bytecode oracle. The standard-library image must be identical across Haxe stage zero and two successive Nail rebuilds. Runtime numeric semantics, dot projections and qualified record accessors retain v0.19 behavior.
