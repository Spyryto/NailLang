# NailSeed v0.23 — Inspect expansions and produce a guitar lesson

`--expand` prints the expanded core, without evaluating the program. Generated
binders appear as `tmp@0` and free template references as `global[helper]`.
The output is a diagnostic view of bindings and lowered expressions.

```sh
haxe php.hxml
php build/php/index.php --expand examples/lezione.nail
php build/php/index.php --types examples/lezione.nail
php build/php/index.php examples/lezione.nail | node examples/lesson-html.cjs > lezione.html
haxe js.hxml
node examples/verify-lesson.cjs
```

In JavaScript, use `NailSeed.expand(source)`. The lesson includes an objective,
two bending exercises, and measurable success criteria. The plain JavaScript
baseline produces the same data and HTML (Nail's nominal records additionally
serialize their `$type` field). The example is a draft for classroom use.

A one-to-one macro around `Drill` gives no savings over the constructor.
The example's value here is inspection and a controlled comparison before
introducing shared macros.
