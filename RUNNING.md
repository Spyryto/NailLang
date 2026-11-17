# Eseguire NailLang — v0.48

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

## Test delle operazioni numeriche esatte v0.43

```sh
haxe seed-image.hxml
haxe exact-rounding-test-interp.hxml
haxe exact-rounding-test-js.hxml && node build/tests/exact-rounding.js
haxe exact-rounding-test-php.hxml && php build/tests/php-exact-rounding/index.php
```

Le cinque funzioni sono pure e disponibili nella VM standard. Il bootstrap
esistente può compilare i loro nomi senza modificare parser, formato delle
immagini o set di istruzioni. Non convertono mai `Number` in `Exact`
automaticamente.

## v0.44 — Contratti di divisione espliciti

```sh
haxe seed-image.hxml
haxe explicit-relations-test-interp.hxml
haxe explicit-relations-test-js.hxml && node build/tests/explicit-relations.js
haxe explicit-relations-test-php.hxml && php build/tests/php-explicit-relations/index.php
```

La sintassi `def name x y : Div = expression ;` è cancellata dal
compilatore dopo la verifica statica. Una compilazione pura tramite
`BootRuntime.compile` **non** esegue il TypeChecker Haxe: come già
per gli altri contratti, validare il codice con `TypeChecker.check`
prima di distribuirlo o concedere capability.

## Test v0.45 del nuovo dominio numerico

```sh
haxe seed-image.hxml
haxe modern-numbers-test-interp.hxml
haxe modern-numbers-test-js.hxml && node build/tests/modern-numbers.js
haxe modern-numbers-test-php.hxml && php build/tests/php-modern-numbers/index.php
```

I programmi nuovi iniziano con `nail 0.45 ;`. La dichiarazione è
linguaggio, non un commento; una VM che non supporta la versione del
sorgente deve rifiutarla. Nelle distribuzioni odierne, l'API
`BootRuntime.compile` verifica l'header prima di scegliere
l'unico compilatore del dialetto moderno.

## Test v0.46 (relazioni e bootstrap moderno)

```sh
haxe seed-image.hxml
haxe arithmetic-relations-test-interp.hxml
haxe arithmetic-relations-test-js.hxml && node build/tests/arithmetic-relations.js
haxe arithmetic-relations-test-php.hxml && php build/tests/php-arithmetic-relations/index.php
haxe modern-bootstrap-test-js.hxml && node build/tests/modern-bootstrap.js
```

`nail 0.45 ;` è compatibile; `nail 0.46 ;` abilita le nuove
relazioni `Add`, `Sub` e `Mul`. Nessuna modifica al formato della VM.
Il test `modern-bootstrap-test-interp.hxml` costruisce un'immagine
sperimentale della stdlib in semantica moderna e ne confronta i tre stadi
di compilazione; la distribuzione mantiene l'immagine legacy finché la
migrazione completa dei test e dell'ABI non è terminata.

The whole-stdlib modern bootstrap test runs on Node for speed; the
Haxe `--interp` variant remains available for debugging.

## v0.47 — Compilatore Nail indipendente dal parser Haxe

```sh
haxe seed-image.hxml
haxe rebootstrap-node.hxml
node build/tests/rebootstrap-node.js
haxe boot-js.hxml
haxe boot-php.hxml
node -e 'const {NailSeedBoot}=require("./build/boot/js/nailseed-boot.js"); console.log(NailSeedBoot.create().runPlain("nail 0.47 ; 1 / 3 + 1 / 6 ;"))'
php build/boot/php/index.php examples/numbers-047.nail
```

I due compilati `boot` incorporano la **nuova immagine bootstrap v2**,
prodotta dal compilatore Nail con le regole `Int`, `Ratio`, `Float`.
Non richiedono il parser Haxe né Haxe sulla macchina di esecuzione.
Sono disponibili anche come ZIP separati nelle GitHub Releases, senza
appesantire la distribuzione tradizionale della VM completa. L'immagine
standalone JSON si trova in `build/bootstrap/self-image.json`.

```sh
haxe official-bootstrap-test-interp.hxml
haxe official-bootstrap-test-js.hxml && node build/tests/official-bootstrap.js
haxe official-bootstrap-test-php.hxml && php build/tests/php-official-bootstrap/index.php
haxe modern-bootstrap-test-js.hxml && node build/tests/modern-bootstrap.js
```

Le immagini v2 includono `languageVersion: "0.47"` e il decoder
v0.47 rifiuta quelle con una versione del compilatore non supportata.
Questo campo riguarda il **compiler bootstrap**, non la versione ABI
dei moduli compilati separatamente (`runtime-module.v1`).

**Limite residuo:** l'esecuzione `BootRuntime.run` non invoca
automaticamente `TypeChecker`; quando serve la garanzia delle firme
dichiarate, eseguire `TypeChecker.check` prima della compilazione.

### Ricompilazione senza Node

La procedura `haxe rebootstrap-image.hxml` rimane supportata per un
ambiente che dispone solo di Haxe: produce la stessa immagine con verifica
del punto fisso, ma il suo interprete è più lento della variante Node.

## Moduli compilati con ABI numerico v0.48

```sh
haxe seed-image.hxml
haxe modern-module-abi-test-interp.hxml
haxe modern-module-abi-test-js.hxml && node build/tests/modern-module-abi.js
haxe modern-module-abi-test-php.hxml && php build/tests/php-modern-module-abi/index.php
```

`ModuleLinker.compile`, `compileInferred` e `compilePublic`
accettano ora i programmi con intestazione `nail 0.45 ;` … `nail 0.48 ;`.
Le interfacce `Int`, `Ratio`, `Float` sono serializzate con l'ABI
`int-ratio-float.v1`. I moduli v2 contengono il `sourceVersion`
effettivo; non va dedotto dal tipo dei letterali.

**Sicurezza**: il semplice JSON non prova l'autenticità di un modulo.
Per distribuire moduli non fidati usare le verifiche già presenti
di hash firmato, firma Ed25519 e grant espliciti prima del link.
Le funzioni con vincoli numerici (`: Div`, `: Mul`, ...) non hanno ancora
un ABI relazionale; gli export di quelle funzioni vengono rifiutati.
