# NailSeed v0.21 — Immutable vectors

Vectors are homogeneous values with zero-based indexing. Build one from a list
using `vector`. Existing list syntax and list matching retain their meaning.

```nail
def original = vector [ 10 , 20 , 30 ] ;
def changed = vectorSet original 1 99 ;
vectorGet original 1 ;   # 20
vectorGet changed 1 ;    # 99
vectorLength changed ;   # 3
```

Lookup and length take constant time. Construction and immutable replacement
take linear time. Replacement copies the backing array; no mutable vector
operation is exposed. Invalid, fractional and out-of-range indices raise
errors. Equality compares elements when their types support equality.

The Haxe checker infers `Vector[a]` separately from `[a]`. Both compiler
paths and the source-free runtime use the same primitive implementations
and the existing bytecode instruction set.
