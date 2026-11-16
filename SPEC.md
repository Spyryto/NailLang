# NailSeed 0.6 — Specifica sperimentale

## Obiettivo e compatibilità

Portare la v0.5 più vicino al linguaggio funzionale sorgente voluto, **senza aumentare le cinque espressioni del core**. Restano compatibili i programmi eseguibili nella v0.5, compreso l'ordine di valutazione eager. La fonte della semantica è l'implementazione Haxe e i test `cases.json` / `type-cases.json` identici per interpreter Haxe, JS e PHP.

### Sintassi

```text
expression := ... | "let" name "=" expression "in" expression
                  | "match" expression "with" match-arm match-arm
match-arm  := "|" "[]" "->" expression
            | "|" name "::" name "->" expression
```

`[ ]` è una grafia alternativa per il pattern vuoto. Le due alternative sono obbligatorie e in ordine libero, con una sola occorrenza ciascuna. `name` è un identificatore o `_` (wildcard) solo per i campi `head` e `tail`. Due binding con lo stesso nome in un pattern sono rifiutati. Gli altri operatori conservano precedenze e associatività della v0.5. Ogni token deve essere separato da whitespace. I commenti `# ...` occupano il resto della riga.

Non supportiamo `let rec`; la destra di `let` viene analizzata nell'ambiente precedente. Se un costrutto è annidato e il delimitatore `|` risulta ambiguo, si usano parentesi esplicite. Una terza alternativa di match viene rifiutata.

### Desugaring

`let x = a in b` equivale a `Apply(Lambda("x", b), a)` nel core.

`match xs with | [] -> e | h :: t -> n` equivale schematicamente a:

```text
( fun #list ->
    if #isEmpty #list then e
    else ( fun h -> fun t -> n ) ( #head #list ) ( #tail #list )
) xs
```

Le parole `#list`, `#isEmpty`, `#head` e `#tail` sono interne (non token utente); `#list` viene generata con identificatore fresco. L'espressione `xs` viene valutata una sola volta, mentre solo il ramo selezionato viene valutato. Il desugaring non dipende da un eventuale binding utente di `head`, `tail`, `isEmpty` o `cons`.

### Inferenza dei tipi

Il type checker della v0.5 ha ora un caso speciale per la forma core `Apply(Lambda(name, body), value)`, che equivale a un `let` non ricorsivo. Inferisce il tipo di `value`, generalizza le variabili libere non vincolate dall'ambiente e inferisce `body` con il relativo schema. In un linguaggio puro e senza riferimenti mutabili, questo permette il polimorfismo let locale. Una lambda passata come valore a una funzione conserva invece la regola standard dei parametri monomorfi.

L'inferenza di `match` discende dalle primitive listate private, dalla condizione booleana di `If` e dall'unificazione dei tipi dei due rami: nessuna regola speciale `Match` è richiesta nel checker. Si applicano gli stessi vincoli `Eq` della v0.5.

### Libreria standard

`stdlib.nail` utilizza `match` per implementare `map`, `filter`, `fold`. Conserva `id`, `compose`, `reverse`, `length`; nessuna delle funzioni di libreria è una primitiva host.

### Test e CI

- Test runtime: `cases.json` positivi + negativi, più controllo che l'AST usi esattamente i cinque nodi.
- Test tipi: `type-cases.json` positivi + negativi, più controlli incrementali e non-commit dei fallimenti, inferenza della firma di un `match`.
- GitHub Actions: compila Haxe interpreter, JavaScript/Node.js, PHP 8.3; test di distribuzione, artefatti JS/PHP.

### Limiti

Non è ancora possibile scrivere il parser di Nail interamente in Nail, perché mancano stringhe, rappresentazione dei token, primitive di elaborazione testuale e lettura di sorgenti. Le liste e le closure restano implementate nella VM Haxe, senza TCO e senza sandboxing. Il checker rimane opzionale e il parser non possiede diagnostica con posizioni nel sorgente. I pattern sono limitati alle liste e devono essere esaustivi.
