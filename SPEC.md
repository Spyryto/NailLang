# Record declarations — v0.17 language draft

## Grammar

All punctuation tokens must be separated by whitespace, as elsewhere in Nail.

```text
record-decl = "type" UpperIdentifier "{" (Identifier TypeName)+ "}" ";"
TypeName    = "Number" | "Bool" | "Text" | "String" | PriorRecordName
```

At least one field is required (up to 128); duplicate field names and duplicate type/constructor/accessor names are errors. Type names must start uppercase. The order of fields defines constructor argument order; fields are not mutable or public by index. Recursive/forward type declarations are postponed until algebraic types.

## Static semantics

- `Person` is a new *nominal* type distinct from every other declared type, including those with identical fields.
- Constructors curry each argument, e.g. `Person : Text -> Number -> Person`.
- Each named accessor is a pure function: `Person_name : Person -> Text`.
- `String` aliases `Text` in declarations, with `Text` shown in type signatures.
- Equality of record values requires the same nominal type, then compares corresponding fields structurally. All currently permitted field types are equality-comparable.
- The type checker remains optional in v0.17. Badly typed code may be rejected at runtime, or produce values whose fields have unexpected types, when type-checking is skipped.

## Dynamic semantics

`Record(typeName, StringMap<Value>)` holds the nominal tag and immutable fields (not directly mutable from Nail). The field hash table is built on construction and accessed in expected O(1); this optimizes random access compared with linked lists, at the cost of one map allocation per record. Nominal type ids and offset-based layouts may replace the hash map in a later optimization without changing the source language.

`RecordType` is a **top-level declaration**, not an expression node, and is lowered to a curried constructor plus one accessor per field. Two internal operations `#recordMake` and `#recordGet` are implemented by the host VM. No new bytecode instruction is needed; generated definitions use standard `DEFINE`, `CLOSURE`, `CONST`, `LOAD`, `CALL`, etc. The old five Expr constructors remain unchanged.

Both parsers recognize the declaration and yield `SyntaxNode("RecordType", [...])` at the first-class syntax boundary; `SyntaxBridge` validates it, the reference compiler lowers it, and the Nail-written compiler emits the same structured instruction stream. This is intentionally a *restricted form of compile-time code generation*, without a general-purpose macro expander.

## Deferred

Parameterized ADTs, record destructuring and updates, Unicode field names, module-qualified record names, rich type names (`List Person`) and full compile-time hygienic macros. The v0.16 exact numbers experiment is **not integrated** here.
