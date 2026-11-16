# Come eseguire NailSeed — v0.1

[Language Tour](./LANGUAGE-TOUR.md) · [Cookbook](./COOKBOOK.md) · [Indice](../docs/README.md)

**Natura dell'artefatto:** prototipo JavaScript + PHP indipendenti. Tutti i comandi seguenti si eseguono nella cartella `v0.1/`, dopo aver clonato il repository. Gli esempi usano i nomi di file realmente presenti nello snapshot.

## Node.js e PHP 8

```sh
cd v0.1
node NailSeed.js             # self-test JavaScript
php NailSeed.php             # self-test PHP
node -e 'const fs=require("node:fs"); const N=require("./NailSeed.js"); console.log(N.create().run(fs.readFileSync("examples/cookbook-start.nail","utf8")))'
php -r 'require "NailSeed.php"; echo json_encode((new NailSeed())->run(file_get_contents("examples/cookbook-start.nail")));'
```

Il file CLI eseguito direttamente lancia i test; il proprio programma si passa all'API `create().run(source)` (JS) o `(new NailSeed())->run(source)` (PHP). `run` restituisce lo stack dei risultati.

## Aprire il runtime in una pagina web

Un esempio già pronto si trova in [`examples/browser.html`](./examples/browser.html). Non è richiesta una compilazione Haxe. Il bundle JS espone un API JavaScript, ma non crea pulsanti o input da solo: la pagina chiama esplicitamente `run` / `runPlain`.

```html
<script src="NailSeed.js"></script>
<button id="go">Esegui Nail</button><pre id="result"></pre>
<script>
document.getElementById('go').addEventListener('click', () => {
  const vm = NailSeed.create();
  const output = vm.run('3 4 +');
  document.getElementById('result').textContent = JSON.stringify(output);
});
</script>
```

Apri con un browser moderno. Per risorse caricate con `fetch` (es. moduli o sorgenti esterni) usa un server HTTP statico anziché il protocollo `file://`; ad esempio `php -S localhost:8000` dalla cartella della versione. Per v0.38, le capability host non vengono concesse automaticamente dal browser.

