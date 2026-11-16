# Nail Language Tour — v0.3

> interpreter JavaScript, senza target PHP · Argomento distintivo: **Functional core in cinque forme**.

[Indice delle versioni](../docs/README.md) · [Cookbook](./COOKBOOK.md) · [Esecuzione](./RUNNING.md) · [README](./README.md) · [SPEC](./SPEC.md) · [casi runtime](./cases.json) · [stdlib.nail](./stdlib.nail)

**Percorso:** [versione precedente](../v0.2/LANGUAGE-TOUR.md) → **v0.3** → [versione successiva](../v0.4/LANGUAGE-TOUR.md).

## Che cosa imparo in questa versione?

Cinque forme di espressione nel core; `map`, `filter` e `fold` sono implementate nella libreria Nail. Solo runtime JavaScript.

```nail
def twice x = x * 2 ;
map twice [ 1 , 2 , 3 ] ;
```

## Primo programma

```nail
def twice x = x * 2 ;
twice 21 ;
```

I delimitatori e gli operatori vanno separati da spazi: `f ( x + 1 ) ;` è corretto. Il punto e virgola termina una definizione o un'espressione top-level. `def` introduce una funzione; l'applicazione è per giustapposizione (`twice 21`).

## Funzioni e valori

```nail
def add a b = a + b ;
def addTen = add 10 ;
addTen 32 ;
```

Le funzioni sono currificate: `add 10` restituisce una funzione che accetta il secondo argomento. Non serve gestire manualmente lo stack, anche se VM e bytecode possono farlo internamente.

## Liste e libreria standard

```nail
def twice x = x * 2 ;
map twice [ 1 , 2 , 3 ] ;
```

La `stdlib.nail` è caricata negli esempi host delle release Haxe via `vm.loadStdlib()`. In JS v0.3 va caricata esplicitamente. `map` non è necessariamente una primitiva della VM: verifica il suo codice in `stdlib.nail`.

## Core AST

Sotto la superficie restano cinque varianti: Literal, Var, Lambda, Apply, If. Le definizioni top-level e i costrutti di comodità si traducono in queste forme. Leggi `NailSeed.js` per il core e `stdlib.nail` per le funzioni di lista.

## Laboratorio guidato

1. Leggi [i tre esempi del cookbook](./COOKBOOK.md) e modifica un solo valore alla volta.
2. Esegui il percorso spiegato in [RUNNING.md](./RUNNING.md) (per i laboratori, esegui i test Haxe/JS/PHP).
3. Confronta il risultato con `cases.json` e la specifica `SPEC.md`; controlla la differenza fra parsing, type checking, runtime e tooling.
4. Apri la [versione v0.3 nel repository](https://github.com/Spyryto/NailSeed/tree/main/v0.3) e cerca il test associato alla feature.

## Cosa non dedurre

Questa è la documentazione di **uno snapshot**: gli esperimenti successivi non aggiornano retroattivamente la semantica qui descritta. Il language tour non equivale a un contratto di stabilità, né garantisce che ogni costrutto sia supportato in tutti i percorsi di compilazione, nelle demo HTML o nel parser self-hosted. Per i confini esatti usa i test e `SPEC.md`.
