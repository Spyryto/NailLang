# NailSeed v0.3

**Minimal Functional Core** — primo esperimento progettato principalmente per sottrazione.

- `NailSeed.js`: interprete di riferimento JavaScript, senza dipendenze, AST di **cinque espressioni**.
- `stdlib.nail`: `map`, `filter`, `fold`, `compose`, `reverse`, `length`, `id` scritti interamente in Nail.
- `cases.json`: 36 casi di prova portabili (24 positivi e 12 negativi).
- `test.js`: runner Node con un controllo addizionale sull'AST (**37 test**).
- `SPEC.md`: grammatica, semantica, limitazioni e prospettive.

Per provare:

```sh
node test.js
```

Esempio Nail:

```nail
def twice x = x * 2 ;
map twice [ 1 , 2 , 3 ] ;
```

Caricare `stdlib.nail` prima di eseguire `map`. Le primitive dello stack di Forth non fanno parte della sintassi, e `map` non è una primitiva della VM.

**Nota:** questa versione non ha ancora un runtime PHP; è volutamente un esperimento JS-first. La compatibilità Scriptable è progettuale, non ancora testata sul dispositivo.
