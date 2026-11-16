# Nail Cookbook — v0.2

[Language tour](./LANGUAGE-TOUR.md) · [Esecuzione JS/PHP/browser](./RUNNING.md) · [indice](../docs/README.md)

Ricette progressive per usare **questa** versione, non le feature delle release successive. Separare gli snippet in file diversi quando ridefiniscono lo stesso nome; leggere sempre i risultati come valori restituiti dalla VM, non come output automatico della pagina web.

## Ricetta 1 — risultato immediato

File pronto: [`examples/cookbook-start.nail`](./examples/cookbook-start.nail).

```nail
def twice x = x * 2 ;
twice 21 ;
```

**Risultato atteso:** `42` come valore dell'espressione. Per usarlo da Node/PHP segui [RUNNING.md](./RUNNING.md).

## Ricetta 2 — trasformare una lista senza stack

```nail
def twice x = x * 2 ;
[ 1 , 2 , 3 ] |> map twice ;
```

**Risultato atteso:** `[2, 4, 6]`. `|>` rende leggibile la pipeline.

## Ricetta 3 — Funzioni, closure e pipeline

```nail
def twice x = x * 2 ;
[ 1 , 2 , 3 ] |> map twice ;
```

La superficie passa a `def`, applicazione curried, `fun`, `if` e `|>`; niente operazioni esplicite di stack.

## Allenamento: studiare l'implementazione

- Trova il percorso dal sorgente al valore usando [SPEC](./SPEC.md).
- Riscrivi l'esempio usando una funzione ausiliaria, poi verifica un caso negativo (nome non definito, tipo incompatibile, pattern non esaustivo quando applicabile).
- Nelle release Haxe, confronta `test-interp.hxml`, `test-js.hxml` e `test-php.hxml`; una build riuscita non prova automaticamente il funzionamento della demo browser.
