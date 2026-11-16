# NailSeed v0.24 — Reusable macro modules

A compilation unit can import a specific macro from a named module.

```nail
import timedDrill from guitar ;
expand timedDrill " Ripeti a tempo " " 60 " " Fai un bending ogni due battiti "
  " 4 arrivi intonati su 5 " ;
```

The example uses one shared definition for bending and vibrato. It supplies
the tempo and score once per exercise and uses the same wording convention
in both lessons. The 0.23 comparison against plain JavaScript still checks
equivalent data and HTML.

```sh
haxe php.hxml
php build/php/index.php --macro-dir examples/macros --expand examples/lezione.nail
php build/php/index.php --macro-dir examples/macros --types examples/lezione.nail
php build/php/index.php --macro-dir examples/macros examples/lezione.nail | node examples/lesson-html.cjs > lezione.html
haxe js.hxml
node examples/verify-lesson.cjs
node examples/audit-macros.cjs
```

JavaScript callers can provide a resolver `name => sourceOrNull` to
`NailSeed.expand`, the VM, the checker, and the bootstrap runtime.
See [SPEC.md](SPEC.md) for scope and [MACRO-AUDIT.md](MACRO-AUDIT.md)
for measured opportunities.
