# Come eseguire NailSeed — v0.29

[Language Tour](./LANGUAGE-TOUR.md) · [Cookbook](./COOKBOOK.md) · [Indice](../docs/README.md)

**Natura dell'artefatto:** laboratorio di implementazione Haxe, non dialetto Nail pronto all'uso. Tutti i comandi seguenti si eseguono nella cartella `v0.29/`, dopo aver clonato il repository. Gli esempi usano i nomi di file realmente presenti nello snapshot.

## Esperimento numerico (non interprete Nail integrato)

Sono necessari Haxe 4.3.x, Node.js per il test JS e PHP 8 per il test PHP. Dal terminale:

```sh
cd v0.29
haxe test-interp.hxml
haxe test-js.hxml && node build/numeric-lab.js
haxe test-php.hxml && php build/php/index.php
haxe candidate-test-interp.hxml
haxe candidate-test-js.hxml && node build/numeric-model.js
haxe candidate-test-php.hxml && php build/php-numeric-model/index.php
haxe numeric-fast-test-interp.hxml
haxe numeric-fast-test-js.hxml && node build/fast-numeric.js
haxe numeric-fast-test-php.hxml && php build/php-fast-numeric/index.php
```

I programmi compilati qui sono **runner di test numerici**, non un'interprete Nail da lanciare su un file `.nail` e non un modulo pubblico predisposto per una pagina HTML. Per una sintassi esatta eseguibile consulta [v0.29-runtime](../v0.29-runtime/RUNNING.md).
