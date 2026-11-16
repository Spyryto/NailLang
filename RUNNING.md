# Eseguire NailLang — v0.42

[Language Tour](./LANGUAGE-TOUR.md) · [Cookbook](./COOKBOOK.md) · [Versioni](./docs/versions.md)

Dalla **radice del repository**. Requisiti per compilare: Haxe 4.3.x. Per eseguire: Node.js 22 o PHP 8.

```sh
haxe seed-image.hxml
haxe js.hxml
haxe php.hxml
```

Sono i runtime/interpreti **scritti in Haxe**, compilati in JS e PHP, non un transpiler sorgente Nail → JS/PHP.

## JavaScript da riga di comando

```sh
node -e 'const fs=require("node:fs"); const {NailSeed}=require("./build/js/nailseed.js"); const vm=NailSeed.create(); vm.loadStdlib(); console.log(vm.runPlain(fs.readFileSync("examples/cookbook-start.nail","utf8")));'
```

Il nome esportato `NailSeed` è conservato temporaneamente per compatibilità, benché il repository si chiami NailLang.

## PHP da riga di comando

```sh
php build/php/index.php examples/cookbook-start.nail
php build/php/index.php --types examples/cookbook-start.nail
```

## JavaScript in una pagina web

`examples/browser.html` carica `../build/js/nailseed.js`. Dopo la compilazione, dalla radice avvia:

```sh
php -S localhost:8000
```

Apri <http://localhost:8000/examples/browser.html>. Per incorporare il runtime altrove, includi lo script generato e chiama `NailSeed.create().runPlain(source)`, caricando la libreria standard tramite `vm.loadStdlib()` quando necessaria.

## Test mirati v0.39

```sh
haxe seed-image.hxml
haxe host-text-writes-test-interp.hxml
haxe host-text-writes-test-js.hxml && node build/tests/host-text-writes.js
haxe host-text-writes-test-php.hxml && php build/tests/php-host-text-writes/index.php
```

`NailHost.readTextResult` e `NailHost.writeTextResult` richiedono grant espliciti e isolati per modulo. Non sono disponibili automaticamente nella CLI o nel browser; vedi [HOST-CAPABILITIES.md](./HOST-CAPABILITIES.md). Le build e i test delle versioni storiche restano nei tag rispettivi.

## Test di integrità delle immagini v0.40

```sh
haxe seed-image.hxml
haxe trusted-module-images-test-interp.hxml
haxe trusted-module-images-test-js.hxml && node build/tests/trusted-module-images.js
haxe trusted-module-images-test-php.hxml && php build/tests/php-trusted-module-images/index.php
```

La CLI ordinaria esegue programmi Nail. Per collegare moduli compilati con
capability host protette da pin, integra la API Haxe
`ModuleLinker.linkTrustedImages`. Vedi [HOST-CAPABILITIES.md](./HOST-CAPABILITIES.md).

## Test di revoca v0.41

```sh
haxe seed-image.hxml
haxe revocable-capabilities-test-interp.hxml
haxe revocable-capabilities-test-js.hxml && node build/tests/revocable-capabilities.js
haxe revocable-capabilities-test-php.hxml && php build/tests/php-revocable-capabilities/index.php
```

Questi test coprono revoca post-link, grant indipendenti, capability
condivise e funzioni scriventi parzialmente applicate, in Haxe/JS/PHP.

## Test manifest firmati v0.42

```sh
haxe seed-image.hxml
haxe signed-manifests-test-interp.hxml
haxe signed-manifests-test-js.hxml && node build/tests/signed-manifests.js
haxe signed-manifests-test-php.hxml && php build/tests/php-signed-manifests/index.php
```

Il test Haxe `--interp` invoca Node.js come verificatore crittografico
di test. L'API di produzione `linkSignedImages` verifica automaticamente
Ed25519 solo in Node.js o PHP (con estensione sodium attiva).
Per applicazioni web/browser o altri host è necessario integrare un
verificatore Ed25519 sincrono affidabile con
`linkSignedImagesWithVerifier`, altrimenti il controllo fallisce.
