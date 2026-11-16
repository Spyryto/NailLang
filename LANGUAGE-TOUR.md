# Nail Language Tour — v0.2

> prototipo JavaScript + PHP indipendenti · Argomento distintivo: **Funzioni, closure e pipeline**.

[Indice delle versioni](../docs/README.md) · [Cookbook](./COOKBOOK.md) · [Esecuzione](./RUNNING.md) · [SPEC](./SPEC.md)

**Percorso:** [versione precedente](../v0.1/LANGUAGE-TOUR.md) → **v0.2** → [versione successiva](../v0.3/LANGUAGE-TOUR.md).

## Che cosa imparo in questa versione?

La superficie passa a `def`, applicazione curried, `fun`, `if` e `|>`; niente operazioni esplicite di stack.

```nail
def twice x = x * 2 ;
[ 1 , 2 , 3 ] |> map twice ;
```

## Dalla pila alle funzioni

```nail
def inc = + 1 ;
def makeAdder x = fun y -> x + y ;
[ 1 , 2 , 3 ] |> map inc ;
```

Le funzioni catturano l'ambiente lessicale e supportano l'applicazione parziale. `if ... then ... else ...`, operatori con precedenza e `|>` sono sintassi di superficie; `s:Ciao%20mondo` è la stringa codificata del prototipo.

## Implementazione

Confronta i due interpreti AST indipendenti in `NailSeed.js` e `NailSeed.php`. Non c'è ancora la VM Haxe, né un checker HM.

## Laboratorio guidato

1. Leggi [i tre esempi del cookbook](./COOKBOOK.md) e modifica un solo valore alla volta.
2. Esegui il percorso spiegato in [RUNNING.md](./RUNNING.md) (per i laboratori, esegui i test Haxe/JS/PHP).
3. Confronta il risultato con la specifica `SPEC.md`; controlla la differenza fra parsing, type checking, runtime e tooling.
4. Apri la [versione v0.2 nel repository](https://github.com/Spyryto/NailSeed/tree/main/v0.2) e cerca il test associato alla feature.

## Cosa non dedurre

Questa è la documentazione di **uno snapshot**: gli esperimenti successivi non aggiornano retroattivamente la semantica qui descritta. Il language tour non equivale a un contratto di stabilità, né garantisce che ogni costrutto sia supportato in tutti i percorsi di compilazione, nelle demo HTML o nel parser self-hosted. Per i confini esatti usa i test e `SPEC.md`.
