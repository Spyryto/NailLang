# Nail Language Tour — v0.16

> laboratorio di implementazione Haxe, non dialetto Nail pronto all'uso · Argomento distintivo: **Laboratorio dei numeri esatti**.

[Indice delle versioni](../docs/README.md) · [Cookbook](./COOKBOOK.md) · [Esecuzione](./RUNNING.md) · [README](./README.md) · [SPEC](./SPEC.md)

**Percorso:** [versione precedente](../v0.15/LANGUAGE-TOUR.md) → **v0.16** → [versione successiva](../v0.17/LANGUAGE-TOUR.md).

## Che cosa imparo in questa versione?

La sintassi mostrata è una PROPOSTA di dialetto, non un programma eseguibile qui. Questa cartella contiene esperimenti Haxe sui razionali e test JS/PHP compilati.

```nail
# nail: 0.16
def thirds = 1/3 ;
```

**Attenzione:** questo esempio descrive la sintassi candidata del linguaggio. Non copiarlo nel runtime standard di Nail aspettandoti che funzioni: qui si studia l'implementazione numerica, non una nuova funzione eseguibile da ogni programma Nail.

## Modello mentale

Separa la rappresentazione dei valori dalla sintassi di superficie: big integer/rational e test cross-target possono esistere senza che la grammatica del linguaggio li riconosca. Consulta `SPEC.md` e i test Haxe per vedere dove finisce il prototipo.

## Laboratorio guidato

1. Leggi [i tre esempi del cookbook](./COOKBOOK.md) e modifica un solo valore alla volta.
2. Esegui il percorso spiegato in [RUNNING.md](./RUNNING.md) (per i laboratori, esegui i test Haxe/JS/PHP).
3. Confronta il risultato con la specifica `SPEC.md`; controlla la differenza fra parsing, type checking, runtime e tooling.
4. Apri la [versione v0.16 nel repository](https://github.com/Spyryto/NailSeed/tree/main/v0.16) e cerca il test associato alla feature.

## Cosa non dedurre

Questa è la documentazione di **uno snapshot**: gli esperimenti successivi non aggiornano retroattivamente la semantica qui descritta. Il language tour non equivale a un contratto di stabilità, né garantisce che ogni costrutto sia supportato in tutti i percorsi di compilazione, nelle demo HTML o nel parser self-hosted. Per i confini esatti usa i test e `SPEC.md`.
