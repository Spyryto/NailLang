# Nail Language Tour — v0.4

> snapshot Haxe compilabile per JavaScript e PHP · Argomento distintivo: **Un’unica implementazione Haxe**.

[Indice delle versioni](../docs/README.md) · [Cookbook](./COOKBOOK.md) · [Esecuzione](./RUNNING.md) · [README](./README.md) · [SPEC](./SPEC.md) · [casi runtime](./cases.json) · [Main.hx](./src/Main.hx) · [parser Haxe](./src/nail/Parser.hx) · [stdlib.nail](./stdlib.nail)

**Percorso:** [versione precedente](../v0.3/LANGUAGE-TOUR.md) → **v0.4** → [versione successiva](../v0.5/LANGUAGE-TOUR.md).

## Che cosa imparo in questa versione?

Stessa semantica Haxe, JavaScript e PHP; il linguaggio è eseguito da un interprete compilato, non transpilato direttamente in JS/PHP.

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

## Laboratorio guidato

1. Leggi [i tre esempi del cookbook](./COOKBOOK.md) e modifica un solo valore alla volta.
2. Esegui il percorso spiegato in [RUNNING.md](./RUNNING.md) (per i laboratori, esegui i test Haxe/JS/PHP).
3. Confronta il risultato con `cases.json` e la specifica `SPEC.md`; controlla la differenza fra parsing, type checking, runtime e tooling.
4. Apri la [versione v0.4 nel repository](https://github.com/Spyryto/NailSeed/tree/main/v0.4) e cerca il test associato alla feature.

## Cosa non dedurre

Questa è la documentazione di **uno snapshot**: gli esperimenti successivi non aggiornano retroattivamente la semantica qui descritta. Il language tour non equivale a un contratto di stabilità, né garantisce che ogni costrutto sia supportato in tutti i percorsi di compilazione, nelle demo HTML o nel parser self-hosted. Per i confini esatti usa i test e `SPEC.md`.
