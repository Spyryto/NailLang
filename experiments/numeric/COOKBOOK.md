# Nail Cookbook — v0.28

[Language tour](./LANGUAGE-TOUR.md) · [Esecuzione JS/PHP/browser](./RUNNING.md) · [indice](../docs/README.md)

Ricette progressive per usare **questa** versione, non le feature delle release successive. Separare gli snippet in file diversi quando ridefiniscono lo stesso nome; leggere sempre i risultati come valori restituiti dalla VM, non come output automatico della pagina web.

## Ricetta 1 — confronto numerico riproducibile

La cartella è un laboratorio, non un'interprete Nail completo. Esegui i tre target tramite le istruzioni in [RUNNING.md](./RUNNING.md); usa la stessa matrice di test per confrontare il comportamento aritmetico.

## Ricetta 2 — evitare le false aspettative

```haxe
var a = NumericCandidate.exact("0.1");
var b = NumericCandidate.exact("0.2");
```

È materiale di laboratorio Haxe: non è un programma Nail eseguibile da browser o CLI standard.

## Ricetta 3 — esperimento controllato

Cambia un input alla volta nei test della cartella: intero, decimale, frazione; verifica differenze tra JS e PHP e annota i limiti di intervallo, precisione e costo. Per usare davvero i letterali esatti nel linguaggio, passa a [v0.29-runtime](../v0.29-runtime/LANGUAGE-TOUR.md).
