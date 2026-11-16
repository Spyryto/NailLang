# Come eseguire NailSeed — v0.3

[Language Tour](./LANGUAGE-TOUR.md) · [Cookbook](./COOKBOOK.md) · [Indice](../docs/README.md)

**Natura dell'artefatto:** interpreter JavaScript, senza target PHP. Tutti i comandi seguenti si eseguono nella cartella `v0.3/`, dopo aver clonato il repository. Gli esempi usano i nomi di file realmente presenti nello snapshot.

## Node.js (nessun target PHP in questa versione)

```sh
cd v0.3
node test.js
node -e 'const fs=require("node:fs"); const {NailSeed3}=require("./NailSeed.js"); const vm=NailSeed3.create(); vm.run(fs.readFileSync("stdlib.nail","utf8")); console.log(vm.run(fs.readFileSync("examples/cookbook-start.nail","utf8")));'
```

La `stdlib.nail` non viene caricata automaticamente dall'interprete JS v0.3. Qui **non** esiste un runtime PHP: passa alla v0.4 per i target generati da Haxe.

## Aprire il runtime in una pagina web

Un esempio già pronto si trova in [`examples/browser.html`](./examples/browser.html). Non è richiesta una compilazione Haxe. Il bundle JS espone un API JavaScript, ma non crea pulsanti o input da solo: la pagina chiama esplicitamente `run` / `runPlain`.

```html
<script src="NailSeed.js"></script>
<button id="go">Esegui Nail</button><pre id="result"></pre>
<script>
document.getElementById('go').addEventListener('click', () => {
  const vm = NailSeed3.create();
  const output = vm.run('def twice x = x * 2 ; twice 21 ;');
  document.getElementById('result').textContent = JSON.stringify(output);
});
</script>
```

Apri con un browser moderno. Per risorse caricate con `fetch` (es. moduli o sorgenti esterni) usa un server HTTP statico anziché il protocollo `file://`; ad esempio `php -S localhost:8000` dalla cartella della versione. Per v0.38, le capability host non vengono concesse automaticamente dal browser.

