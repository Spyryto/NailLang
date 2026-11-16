# Nail Language Tour — v0.29

> laboratorio di implementazione Haxe, non dialetto Nail pronto all'uso · Argomento distintivo: **Numeri esatti compatti e dialetto isolato**.

[Indice delle versioni](../docs/README.md) · [Cookbook](./COOKBOOK.md) · [Esecuzione](./RUNNING.md) · [README](./README.md) · [SPEC](./SPEC.md)

**Percorso:** [versione precedente](../v0.28/LANGUAGE-TOUR.md) → **v0.29** → [versione successiva](../v0.29-runtime/LANGUAGE-TOUR.md).

## Che cosa imparo in questa versione?

Laboratorio Haxe separato con limite di fast path intero ±2^26; ancora nessun parser/VM Nail integrato per questo dialetto.

```haxe
var sum = numeric.FastNumber.arithmetic(
  "+", numeric.FastNumber.exact("0.1"), numeric.FastNumber.exact("0.2"));
trace(numeric.FastNumber.encodeExact(sum)); // E:3/10
```

**Attenzione:** questo esempio descrive l'API Haxe di laboratorio. Non copiarlo nel runtime standard di Nail aspettandoti che funzioni: qui si studia l'implementazione numerica, non una nuova funzione eseguibile da ogni programma Nail.

## Modello mentale

Separa la rappresentazione dei valori dalla sintassi di superficie: big integer/rational e test cross-target possono esistere senza che la grammatica del linguaggio li riconosca. Consulta `SPEC.md` e i test Haxe per vedere dove finisce il prototipo.

## Laboratorio guidato

1. Leggi [i tre esempi del cookbook](./COOKBOOK.md) e modifica un solo valore alla volta.
2. Esegui il percorso spiegato in [RUNNING.md](./RUNNING.md) (per i laboratori, esegui i test Haxe/JS/PHP).
3. Confronta il risultato con la specifica `SPEC.md`; controlla la differenza fra parsing, type checking, runtime e tooling.
4. Apri la [versione v0.29 nel repository](https://github.com/Spyryto/NailSeed/tree/main/v0.29) e cerca il test associato alla feature.

## Cosa non dedurre

Questa è la documentazione di **uno snapshot**: gli esperimenti successivi non aggiornano retroattivamente la semantica qui descritta. Il language tour non equivale a un contratto di stabilità, né garantisce che ogni costrutto sia supportato in tutti i percorsi di compilazione, nelle demo HTML o nel parser self-hosted. Per i confini esatti usa i test e `SPEC.md`.
