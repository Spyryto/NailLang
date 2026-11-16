# NailSeed v0.5 — Haxe type inference

Evoluzione **Haxe-first** della v0.4. Il nucleo di esecuzione rimane invariato: `Literal`, `Var`, `Lambda`, `Apply`, `If`. Il nuovo modulo `TypeChecker` effettua inferenza statica Hindley–Milner su questi stessi nodi, senza nuove annotazioni richieste in Nail.

## Esempi

```nail
def id x = x ;
id 42 ;
id true ;
```

I due risultati del checker sono `Number` e `Bool`. Ogni `def` è generalizzata per permettere polimorfismo let-style; durante la propria definizione una funzione ricorsiva rimane monomorfa.

```nail
def twice x = x * 2 ;
map twice [ 1 , 2 , 3 ] ;
```

Dopo `stdlib.nail`, `map` è inferita come una funzione di ordine superiore e il risultato ha tipo `[Number]`.

Le equality primitive `==` / `!=` supportano solo `Number`, `Bool` e liste di valori confrontabili. Il checker usa un vincolo `Eq a`, per esempio `fun x -> x == x` produce `Eq a => a -> Bool`; il confronto tra funzioni viene rifiutato.

## Esecuzione locale

Installare Haxe 4.3.7, Node.js 22 e PHP 8.3 (o compatibili). Nella directory `v0.5`:

```sh
haxe test-interp.hxml         # 37 test runtime originali
haxe type-test-interp.hxml    # test di inferenza
haxe test-js.hxml && node build/tests/test.js
haxe type-test-js.hxml && node build/tests/types.js
haxe test-php.hxml && php build/tests/php/index.php
haxe type-test-php.hxml && php build/tests/php-types/index.php
haxe js.hxml && haxe php.hxml
```

## JavaScript

```javascript
const api = require('./build/js/nailseed.js').NailSeed;
const types = api.createTypeChecker();
types.check('def id x = x ;');
console.log(types.signature('id')); // 'a -> a'
console.log(types.check('id 1 ; id true ;')); // ['Number','Bool']
```

La API `NailSeed.create()` continua a fornire il runtime sperimentale senza controllo statico automatico. `createTypeChecker()` è un'API opzionale distinta, utile per l'editor e la validazione.

## PHP

```sh
php build/php/index.php --types example.nail
php build/php/index.php example.nail
```

La modalità `--types` carica prima la libreria standard e stampa i tipi delle espressioni; senza flag viene eseguito il codice Nail come nella v0.4.

## Struttura

- `src/nail/TypeChecker.hx` — unificazione, occurs check, generalizzazione/istanziazione, vincoli Eq.
- `src/nail/NType.hx` e `TypeScheme.hx` — linguaggio dei tipi (non l'AST runtime).
- `type-cases.json` — prove positive/negative identiche per Haxe, JS e PHP.
- `src/TypeTestMain.hx` — runner dei test di tipo cross-target.
- `stdlib.nail`, `cases.json`, `src/nail/Vm.hx` e parser — conservati dalla v0.4.
- [Workflow di build](../.github/workflows/nailseed-v05.yml) — verifica tutti i target e pubblica gli artefatti generati.

## Limiti deliberati

- Il checker **non viene applicato automaticamente** a `Vm.run()`; il codice si può controllare separatamente o usare la modalità CLI `--types`.
- I tipi inferiti non rappresentano ancora un sistema di effetti, ADT/pattern matching o moduli.
- Le liste sono omogenee a livello statico; l'accesso a `head []` passa il controllo dei tipi ma fallisce a runtime.
- Il runtime resta eager, usa numeri IEEE-754 finiti e limita i passi; non esegue codice non attendibile in una sandbox sicura.
- I vincoli `Eq` sono una piccola estensione della normale inferenza HM.
