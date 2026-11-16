# Come eseguire NailSeed — v0.17.1

[Language Tour](./LANGUAGE-TOUR.md) · [Cookbook](./COOKBOOK.md) · [Indice](../docs/README.md)

**Natura dell'artefatto:** snapshot Haxe compilabile per JavaScript e PHP. Tutti i comandi seguenti si eseguono nella cartella `v0.17.1/`, dopo aver clonato il repository. Gli esempi usano i nomi di file realmente presenti nello snapshot.

## Compilare e usare JS e PHP dalla CLI

Prérequisiti: Haxe 4.3.x, Node.js, PHP 8. I target JS e PHP sono **compilazioni dell'interprete Haxe** (non traduzioni del file `.nail` in JS/PHP). Nella cartella della versione:

```sh
cd v0.17.1
haxe js.hxml
haxe php.hxml
node -e 'const fs=require("node:fs"); const {NailSeed}=require("./build/js/nailseed.js"); const vm=NailSeed.create(); vm.loadStdlib(); console.log(vm.runPlain(fs.readFileSync("examples/cookbook-start.nail","utf8")));'
php build/php/index.php examples/cookbook-start.nail
```

`NailSeed.create()` crea un interprete; `loadStdlib()` carica il codice Nail incorporato come risorsa Haxe; `runPlain(source)` restituisce dati serializzabili. Il binario PHP `build/php/index.php` legge il/i file passati come argomenti ed emette una rappresentazione JSON per ogni risultato.

### Verifica dei tipi

Il checker è separato dall'esecuzione: si può usare l'API `NailSeed.createTypeChecker()` quando esposta dallo snapshot, oppure il runner di inferenza `type-test-*.hxml`. Per il supporto preciso ai flag CLI consulta `src/Main.hx`, senza presupporre che tutte le versioni accettino gli stessi argomenti.

### Percorsi del bytecode e del bootstrap

La v0.10 introduce ByteVM e compilatore Nail. Per studiare questo percorso usa `bytecode-test-interp.hxml` e, se presenti, i corrispondenti `bytecode-test-js.hxml` / `bytecode-test-php.hxml`. Per le immagini bootstrap, genera prima con `haxe seed-image.hxml` e usa i test `boot-test-*`; non confondere il boot bundle con il normale `build/js/nailseed.js`.

## Aprire il runtime in una pagina web

Un esempio già pronto si trova in [`examples/browser.html`](./examples/browser.html). **Prima esegui `haxe js.hxml`**, perché la pagina referenzia `build/js/nailseed.js`. Il bundle JS espone un API JavaScript, ma non crea pulsanti o input da solo: la pagina chiama esplicitamente `run` / `runPlain`.

```html
<script src="build/js/nailseed.js"></script>
<button id="go">Esegui Nail</button><pre id="result"></pre>
<script>
document.getElementById('go').addEventListener('click', () => {
  const vm = NailSeed.create();
  vm.loadStdlib();
  const output = vm.runPlain('def twice x = x * 2 ; twice 21 ;');
  document.getElementById('result').textContent = JSON.stringify(output);
});
</script>
```

Apri con un browser moderno. Per risorse caricate con `fetch` (es. moduli o sorgenti esterni) usa un server HTTP statico anziché il protocollo `file://`; ad esempio `php -S localhost:8000` dalla cartella della versione. Per v0.38, le capability host non vengono concesse automaticamente dal browser.

