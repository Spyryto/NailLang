# Nail Language Tour — v0.25

> snapshot Haxe compilabile per JavaScript e PHP · Argomento distintivo: **Trasformazione dichiarazioni record**.

[Indice delle versioni](../docs/README.md) · [Cookbook](./COOKBOOK.md) · [Esecuzione](./RUNNING.md) · [README](./README.md) · [SPEC](./SPEC.md) · [casi runtime](./cases.json) · [Main.hx](./src/Main.hx) · [parser Haxe](./src/nail/Parser.hx) · [stdlib.nail](./stdlib.nail)

**Percorso:** [versione precedente](../v0.24/LANGUAGE-TOUR.md) → **v0.25** → [versione successiva](../v0.26/LANGUAGE-TOUR.md).

## Che cosa imparo in questa versione?

Le dichiarazioni record diventano definizioni ispezionabili prima del bytecode; si mantiene un oracolo Haxe indipendente.

```nail
def source = parseSource " type Person { name Text age Number } ; " ;
def plan = expandRecordDeclarations source ;
recordExpansionSource plan ;
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

## Tipi statici (v0.5+)

```nail
def identity x = x ;
identity 1 ;
identity true ;
```

Il checker Haxe inferisce schemi Hindley–Milner; esecuzione e controllo statico sono fasi distinte. Per controllare un sorgente usa la CLI `--types` solo nelle versioni che la espongono, oppure l'API del checker.

## `let` e pattern (v0.6+)

```nail
def firstOrZero xs = match xs with
  | [] -> 0
  | head :: rest -> head ;
firstOrZero [ 7 , 8 ] ;
```

Il `match` sulle liste richiede entrambi i casi. `let name = expression in expression` introduce un binding locale non ricorsivo.

## Record nominali (v0.17+)

```nail
type Person { name Text age Number } ;
def mario = Person " Mario " 34 ;
mario . name ;
```

La struttura ha un'identità nominale; la proiezione `person . field` è disponibile da v0.17.1, mentre v0.17 usa getter espliciti.

## Somme algebriche e `match` (v0.18+)

```nail
type TourMaybe a = TourNone | TourSome a ;
def tourValueOrZero o = match o with
 | TourNone -> 0
 | TourSome x -> x ;
tourValueOrZero ( TourSome 9 ) ;
```

I costruttori sono valori e si possono decostruire tramite pattern. Il checker verifica l'esaustività dei casi.

## Macro (v0.22+)

```nail
macro unless condition action = quote (
 if unquote condition then 0 else unquote action
) ;
expand unless false 42 ;
```

Le macro manipolano strutture sintattiche, non stringhe arbitrarie. Dalla v0.24 sono importabili da moduli dedicati; dalla v0.30 esiste anche una API host tipizzata per trasformatori procedurali.

## Laboratorio guidato

1. Leggi [i tre esempi del cookbook](./COOKBOOK.md) e modifica un solo valore alla volta.
2. Esegui il percorso spiegato in [RUNNING.md](./RUNNING.md) (per i laboratori, esegui i test Haxe/JS/PHP).
3. Confronta il risultato con `cases.json` e la specifica `SPEC.md`; controlla la differenza fra parsing, type checking, runtime e tooling.
4. Apri la [versione v0.25 nel repository](https://github.com/Spyryto/NailSeed/tree/main/v0.25) e cerca il test associato alla feature.

## Cosa non dedurre

Questa è la documentazione di **uno snapshot**: gli esperimenti successivi non aggiornano retroattivamente la semantica qui descritta. Il language tour non equivale a un contratto di stabilità, né garantisce che ogni costrutto sia supportato in tutti i percorsi di compilazione, nelle demo HTML o nel parser self-hosted. Per i confini esatti usa i test e `SPEC.md`.
