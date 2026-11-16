# NailSeed v0.6 — Local bindings & exhaustive list patterns

**Haxe-first**, compilato in JavaScript e PHP dallo stesso sorgente. La v0.6 mantiene le **cinque forme** dell'AST (`Literal`, `Var`, `Lambda`, `Apply`, `If`) della v0.5; introduce due costrutti di superficie, entrambi eliminati dal parser tramite *desugaring*.

## Esempi

```nail
def area w h = let base = w * h in base ;
area 6 7 ;

# Per ora il match supporta solo due pattern esaustivi per lista.
def sum xs =
  match xs with
  | [] -> 0
  | head :: rest -> head + sum rest ;
sum [ 1 , 2 , 3 ] ;

# 'let' è non ricorsivo e polimorfico; nessuna annotazione necessaria.
let identity = fun x -> x in
  let ignored = identity 42 in
  identity true ;
```

I token sono **sempre separati da spazi**, inclusi `|`, `::`, `->`, `;`, parentesi e operatori; i newline non terminano un'espressione. La forma `[]` oppure `[ ]` rappresenta la lista vuota.

`match` richiede *esattamente* due rami in ordine arbitrario: uno `[]`, uno `head :: tail`, con identificatori oppure `_` come wildcard. Non esiste ancora il matching su booleani, numeri, record o strutture annidate. Il parser rifiuta rami mancanti o duplicati.

## Cosa è cambiato

- `let name = value in body` diventa `(fun name -> body) value`, con valutazione *eager* del valore.
- Il type checker riconosce l'applicazione diretta di lambda e applica generalizzazione Hindley–Milner anche ai `let` locali (nella versione 0.5 la generalizzazione era disponibile soprattutto per le definizioni globali).
- Il `match` sulle liste diventa un `if` con primitive private `#isEmpty`, `#head`, `#tail`, e closure che legano `head` e `tail`. Lo scrutinee viene calcolato una sola volta; i nomi interni non possono essere scritti dall'utente.
- `stdlib.nail` riscrive **map, filter e fold usando `match`**; non sono native dell'interprete.
- `cases.json` e `type-cases.json` estendono i test di regressione positivi e negativi.

Il checker statico resta un passaggio **opzionale**; il runtime rifiuta gli errori dinamici e non è una sandbox per codice ostile.

## Prova locale

Richiede Haxe 4.3.7, Node.js 22, PHP 8.3 (o versioni compatibili). Dalla cartella `v0.6`:

```sh
haxe test-interp.hxml
haxe type-test-interp.hxml
haxe test-js.hxml && node build/tests/test.js
haxe type-test-js.hxml && node build/tests/types.js
haxe test-php.hxml && php build/tests/php/index.php
haxe type-test-php.hxml && php build/tests/php-types/index.php
haxe js.hxml && haxe php.hxml
```

La [pipeline GitHub Actions](../.github/workflows/nailseed-v06.yml) esegue le tre modalità, prova le API distribuite JS e PHP e pubblica artefatti generati dalla build. I file generati non sono committati.

## Architettura e limiti

Il parser restituisce l'**AST dei cinque costruttori**, senza introdurre `Let` o `Match` nel runtime. Le liste sono celle `Cons` persistenti. Il matching è strettamente esaustivo sulle liste e i pattern non sono nidificabili; le lambda e le definizioni globali restano ricorsive solo dove previsto. Non ci sono stringhe, lexer autogenerato, ottimizzazione tail-call, ADT generali, macro o parser self-hosted. Il prossimo prerequisito sostanziale per il parser scritto in Nail è il supporto a **stringhe e token**, non un ulteriore costrutto di controllo del flusso.

Vedi [SPEC.md](./SPEC.md) per la semantica e le scelte progettuali.
