# NailSeed v0.17.2 — Internal qualified record names

- `type Person { name Text age Number } ;` generates the constructor `Person` plus internal getters `Person.name` and `Person.age`.
- Type checker signatures: `Person.name : Person -> Text` and `Person.age : Person -> Number`.
- The Haxe lowering uses `Define(typeName + "." + fieldName, accessor)`; the Nail-written lowering uses `textConcat ( textConcat name " . " ) fname`.
- Surface `person . name` is unchanged; both parsers lower it to `Apply(Apply(Var("#recordGet"), person), Literal(Text("name")))`. Static checking uses the resolved nominal receiver type and looks up `Type.field`.
- Qualified getters are internal AST/bytecode identifiers; their dotted strings are not new user source tokens. Thus `Person.name person` is **not** accepted source syntax in this version.
- No new core expression form, opcode or primitive. Accessors remain one-argument functions.
- Older underscore-generated aliases are intentionally not emitted in v0.17.2; previous folders retain their original behavior.
- Tests include direct internal AST invocation, signatures, nominal inference, ambiguous fields, bytecode identity and collision freedom with names like `Bag_name`.

Possible future work: once types are inferred, an optimizer can rewrite `person . name` to an internal `Person.name` invocation; this version keeps the existing dynamic `#recordGet` execution path.

The self-hosted Pratt parser examines the token **tag** before handling `.` as field projection; a quoted literal `" . "` remains a text value, not punctuation. Dedicated regression tests cover this distinction.
