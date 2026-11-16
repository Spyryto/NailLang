# Nail Cookbook — v0.35

[Language tour](./LANGUAGE-TOUR.md) · [Esecuzione JS/PHP/browser](./RUNNING.md) · [indice](../docs/README.md)

Ricette progressive per usare **questa** versione, non le feature delle release successive. Separare gli snippet in file diversi quando ridefiniscono lo stesso nome; leggere sempre i risultati come valori restituiti dalla VM, non come output automatico della pagina web.

## Ricetta 1 — risultato immediato

File pronto: [`examples/cookbook-start.nail`](./examples/cookbook-start.nail).

```nail
def twice x = x * 2 ;
twice 21 ;
```

**Risultato atteso:** `42` come valore dell'espressione. Per usarlo da Node/PHP segui [RUNNING.md](./RUNNING.md).

## Ricetta 2 — trasformare un elenco

```nail
def twice x = x * 2 ;
map twice [ 1 , 2 , 3 ] ;
```

**Risultato atteso:** `[2, 4, 6]`. Per v0.3, carica prima `stdlib.nail`; nelle versioni Haxe chiama `vm.loadStdlib()`.

## Ricetta 3 — Record strutturali anonimi chiusi

```nail
def profile = { age = 36 , name = " Ada " } ;
profile . age ;
```

I tipi dei record anonimi dipendono dai nomi e tipi dei campi; sono CHIUSI (nessun row polymorphism o width subtyping).

## Allenamento: studiare l'implementazione

- Trova il percorso dal sorgente al valore usando [README](./README.md) · [SPEC](./SPEC.md) · [casi runtime](./cases.json) · [Main.hx](./src/Main.hx) · [parser Haxe](./src/nail/Parser.hx) · [stdlib.nail](./stdlib.nail).
- Riscrivi l'esempio usando una funzione ausiliaria, poi verifica un caso negativo (nome non definito, tipo incompatibile, pattern non esaustivo quando applicabile).
- Nelle release Haxe, confronta `test-interp.hxml`, `test-js.hxml` e `test-php.hxml`; una build riuscita non prova automaticamente il funzionamento della demo browser.
