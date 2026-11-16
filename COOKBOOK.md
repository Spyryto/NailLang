# Nail Cookbook — v0.1

[Language tour](./LANGUAGE-TOUR.md) · [Esecuzione JS/PHP/browser](./RUNNING.md) · [indice](../docs/README.md)

Ricette progressive per usare **questa** versione, non le feature delle release successive. Separare gli snippet in file diversi quando ridefiniscono lo stesso nome; leggere sempre i risultati come valori restituiti dalla VM, non come output automatico della pagina web.

## Ricetta 1 — risultato immediato

File pronto: [`examples/cookbook-start.nail`](./examples/cookbook-start.nail).

```nail
:square [ dup * ] def
6 square
```

**Risultato atteso:** `36` in cima allo stack. Per usarlo da Node/PHP segui [RUNNING.md](./RUNNING.md).

## Ricetta 2 — elaborare una lista

```nail
1 2 3 3 pack [ dup * ] map
```

**Risultato atteso:** `[1, 4, 9]`. `pack` crea la lista, `map` esegue una quotation per elemento.

## Ricetta 3 — Quotations e composizione su stack

```nail
:square [ dup * ] def
6 square
```

Il sorgente è concatenativo: ogni parola trasforma lo stack. `:square` è un simbolo, `[ ... ]` una quotation; `def` installa nuove parole al livello superiore.

## Allenamento: studiare l'implementazione

- Trova il percorso dal sorgente al valore usando [SPEC](./SPEC.md).
- Riscrivi l'esempio usando una funzione ausiliaria, poi verifica un caso negativo (nome non definito, tipo incompatibile, pattern non esaustivo quando applicabile).
- Nelle release Haxe, confronta `test-interp.hxml`, `test-js.hxml` e `test-php.hxml`; una build riuscita non prova automaticamente il funzionamento della demo browser.
