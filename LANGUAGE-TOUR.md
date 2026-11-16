# Nail Language Tour — v0.1

> prototipo JavaScript + PHP indipendenti · Argomento distintivo: **Quotations e composizione su stack**.

[Indice delle versioni](../docs/README.md) · [Cookbook](./COOKBOOK.md) · [Esecuzione](./RUNNING.md) · [SPEC](./SPEC.md)

## Che cosa imparo in questa versione?

Il sorgente è concatenativo: ogni parola trasforma lo stack. `:square` è un simbolo, `[ ... ]` una quotation; `def` installa nuove parole al livello superiore.

```nail
:square [ dup * ] def
6 square
```

## Lessico e valutazione

- Ogni token è separato da whitespace; `[` e `]` devono essere token autonomi.
- `:name` crea un simbolo; `name` esegue una parola; `[ ... ]` è una quotation immutabile.
- `s:Ciao%20mondo` rappresenta il testo *Ciao mondo*. `#` commenta il resto della riga.
- `dup`, `swap`, `call`, `curry`, `dip`, `map`, `fold` trasformano valori o programmi.

### Composizione e liste

```nail
3 5 [ + ] curry call
1 2 3 3 pack [ dup * ] map
1 2 3 3 pack 0 [ + ] fold
```

## Implementazione

Confronta `NailSeed.js` e `NailSeed.php`: tokenizer, stack, dizionario, valutazione, limiti di passi. Non esistono inferenza statica né AST a cinque forme.

## Laboratorio guidato

1. Leggi [i tre esempi del cookbook](./COOKBOOK.md) e modifica un solo valore alla volta.
2. Esegui il percorso spiegato in [RUNNING.md](./RUNNING.md) (per i laboratori, esegui i test Haxe/JS/PHP).
3. Confronta il risultato con la specifica `SPEC.md`; controlla la differenza fra parsing, type checking, runtime e tooling.
4. Apri la [versione v0.1 nel repository](https://github.com/Spyryto/NailSeed/tree/main/v0.1) e cerca il test associato alla feature.

## Cosa non dedurre

Questa è la documentazione di **uno snapshot**: gli esperimenti successivi non aggiornano retroattivamente la semantica qui descritta. Il language tour non equivale a un contratto di stabilità, né garantisce che ogni costrutto sia supportato in tutti i percorsi di compilazione, nelle demo HTML o nel parser self-hosted. Per i confini esatti usa i test e `SPEC.md`.
