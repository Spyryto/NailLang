# Eseguire NailLang — v0.55

[Language Tour](./LANGUAGE-TOUR.md) · [Cookbook](./COOKBOOK.md) · [Versioni](./docs/versions.md)

Dalla **radice del repository**. Requisiti per compilare: Haxe 4.3.x. Per eseguire: Node.js 22 o PHP 8.

```sh
haxe seed-image.hxml
haxe js.hxml
haxe php.hxml
```

Sono i runtime/interpreti **scritti in Haxe**, compilati in JS e PHP, non un transpiler sorgente Nail → JS/PHP.

## Analisi statica da JavaScript (v0.50)

Dopo `haxe js.hxml`, l'interfaccia completa espone una query statica
senza eseguire il programma:

```sh
node -e 'const {NailSeed}=require("./build/js/nailseed.js"); console.log(NailSeed.analyze("nail 0.50 ; def answer = 42 ; answer ;"));'
```

Questa funzionalità è nella distribuzione *full*, non in quella source-free.
Vedi [docs/ANALYSIS.md](./docs/ANALYSIS.md).

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
Questa era una limitazione della v0.48: dalla v0.49 i vincoli hanno un ABI relazionale v3, accessibile tramite manifesti pubblici espliciti.


## Test dei vincoli n-ari v0.49 e dell'ABI relazionale

Dalla radice, dopo aver generato l'immagine del compilatore:

```sh
haxe seed-image.hxml
haxe nary-relations-test-interp.hxml
haxe nary-relations-test-js.hxml && node build/tests/nary-relations.js
haxe nary-relations-test-php.hxml && php build/tests/php-nary-relations/index.php
haxe relation-module-abi-test-interp.hxml
haxe relation-module-abi-test-js.hxml && node build/tests/relation-module-abi.js
haxe relation-module-abi-test-php.hxml && php build/tests/php-relation-module-abi/index.php
haxe modern-module-abi-test-interp.hxml
haxe modern-module-abi-test-js.hxml && node build/tests/modern-module-abi.js
haxe modern-module-abi-test-php.hxml && php build/tests/php-modern-module-abi/index.php
```

La nuova sintassi si usa inserendo `nail 0.49 ;` all'inizio del file e dichiarando le righe `R : T1 ... Tn Result ;` prima di `def f p1 ... pn : R = ... ;`. La compilazione ordinaria genera sempre bytecode Nail per la VM; **non** genera direttamente codice JavaScript o PHP a partire dal sorgente Nail.

Per moduli con funzioni vincolate, usare `ModuleLinker.compilePublic`: un export locale `: R` serializza tutte le righe nella `relation` del formato `runtime-module.v3`; il consumer importa la funzione usando `PublicSourceModuleImport.relation` con lo stesso contratto. La verifica della firma avviene al link, senza codice sorgente. L'ABI numerico resta `int-ratio-float.v1`. Il compilatore corrente usa **`runtime-module.v3` per tutti i moduli moderni**, anche senza relazioni. I moduli v2 storici vanno aperti con il runtime della relativa release.


### Host functions tipizzate (0.51)

Per aggiungere una funzione host senza introdurre primitive VM,
l'applicazione usa `HostTextGrants.grantFunction(module, symbol,
type, callback, maxCalls)`. Il modulo Nail richiede esplicitamente
`NailHost.symbol` nel manifesto; la firma è controllata dal
linker. Il callback può ricevere valori `Text`, `Bool`,
`Int`, `Ratio`, `Float` e restituire anche un
`CoreResult` con payload atomici. La capability può essere
revocata dopo il link; la quota e i controlli di tipo restano
attivi durante le applicazioni parziali.

Dentro Nail è ora possibile scrivere `Ok` ed `Error` invece
di `CoreOk` e `CoreErr`, anche nei pattern `match`.
Vedi [HOST-CAPABILITIES.md](./HOST-CAPABILITIES.md) e
`host-functions-test-{interp,js,php}.hxml`.


### v0.52 — FFI sicura con liste immutabili

I moduli compilati possono richiedere una funzione host con tipo
`List[T] -> U` o `T -> CoreResult[List[U], Text]`, quando `T` e `U`
sono tipi atomici supportati o ulteriori liste. La dichiarazione del tipo
avviene nel manifesto `PublicSourceModuleImport.scheme`, **non** mediante
nuove parole chiave del linguaggio.

Il callback riceve e restituisce `nail.Value` (per le liste: `Nil` e
`Cons(head, tail)`). L'host non passa direttamente gli array JS o PHP.
Prima dell'invocazione e dopo il risultato, la VM rifiuta elementi
incompatibili, code improprie e valori troppo grandi o annidati
(4096 nodi, profondità 8). Come nella 0.51 valgono permessi espliciti,
revoca, limite di chiamate e sincronismo.

Per eseguire i test in Haxe, JavaScript e PHP:

```sh
haxe seed-image.hxml
haxe host-functions-test-interp.hxml
haxe host-functions-test-js.hxml && node build/tests/host-functions.js
haxe host-functions-test-php.hxml && php build/tests/php-host-functions/index.php
```

L'estensione non introduce `extern` e non modifica il backend: le
funzioni rimangono registrate dal programma host. Il passo successivo
sarà decidere come dichiarare e importare queste dipendenze dal sorgente
Nail senza duplicare quanto presente nel manifesto.


### v0.53 — Import runtime direttamente nel sorgente

Per un modulo Nail compilato separatamente, dichiarare il tipo e
l'import da `NailHost` nel file `.nail`, anche dopo le definizioni:

```nail
nail 0.53 ;
def hello name = greetingHost name ;
import greet as greetingHost from NailHost : Text -> Text ;
```

Ora il programma Haxe può omettere il campo `imports`:

```haxe
var spec:nail.ModuleLinker.PublicSourceModuleSpec = {
  name:'Greeter',
  source:source,
  exports:['hello']
};
var image=nail.ModuleImage.encode(nail.ModuleLinker.compilePublic(spec));
var grants=new nail.HostTextGrants();
grants.grantFunction('Greeter','greet',
  nail.NType.TFunction(nail.NType.TText,nail.NType.TText),
  _ -> nail.Value.Text('ciao'));
var linked=nail.ModuleLinker.linkImages([image],40000000,grants);
```

Il compilatore produce e controlla il manifesto dalla dichiarazione.
Il grant Haxe è ancora necessario: una firma nel sorgente **non**
concede permessi. Gli import sono a livello di modulo, non lessicali;
`import ... from Syntax ;` per macro è indipendente.

```sh
haxe seed-image.hxml
haxe host-source-imports-test-interp.hxml
haxe host-source-imports-test-js.hxml && node build/tests/host-source-imports.js
haxe host-source-imports-test-php.hxml && php build/tests/php-host-source-imports/index.php
```

Per ora solo il compilatore di moduli pubblici interpreta questa nuova
sintassi; gli import runtime di moduli Nail e i namespace qualificati
non sono compresi nell'incremento.


### v0.54 — Compilazione di moduli con import selettivi

Il provider viene compilato una volta, con una propria interfaccia
pubblica verificata. Un programma host può compilare il modulo client
usando direttamente la sua immagine, senza duplicare il tipo dell'import:

```nail
nail 0.54 ;
def say name = greet name ;
import greet from Words ;
```

```haxe
var provider = nail.ModuleImage.encode(
  nail.ModuleLinker.compilePublic({
    name:'Words',
    source:'nail 0.54 ; def greet name = textConcat " Ciao " name ;',
    exports:['greet']
  }));

var client = nail.ModuleImage.encode(
  nail.ModuleLinker.compilePublic({
    name:'Client', source:source, exports:['say'],
    dependencies:[provider]
  }));

// L'immagine del provider serve sia alla compilazione del client,
// sia successivamente al collegamento ed all'esecuzione.
var linked = nail.ModuleLinker.linkImages([client, provider]);
var answer = linked.invoke('Client', 'say', nail.Value.Text('Nail'));
```

Si possono importare anche funzioni polimorfe e vincolate con `Eq`:
la loro descrizione strutturata è conservata nell'interfaccia compilata
dalla 0.54, ma validata sempre contro la firma canonica. Il compilatore
non cerca moduli per nome e il linker continua a rifiutare dipendenze
mancanti, firme incompatibili e ABI diversi.

```sh
haxe seed-image.hxml
haxe module-source-imports-test-interp.hxml
haxe module-source-imports-test-js.hxml && node build/tests/module-source-imports.js
haxe module-source-imports-test-php.hxml && php build/tests/php-module-source-imports/index.php
```

`use Module { ... }` non è ancora stato implementato; la scelta della
sua sintassi e del suo scope è sospesa in attesa di discussione.

## v0.55 — Verifica del compilatore Nail e del provider sperimentale

Il percorso pubblico resta `BootRuntime.compile` o
`ModuleLinker.compilePublic`, con le stesse regole dell'ABI v3. Per
l'esperimento autonomo (senza accesso ad alcuna capability host):

```haxe
var boot = new nail.BootRuntime(60000000);
var source = "nail 0.55 ; def identity x = x ; export identity ;";
var result = boot.invoke("tcCompileDeclaredModulePreview", nail.Value.Text(source));
// result = Ok(TCVerifiedModulePreview [TCWireInterface, Bytecode])
```

L'API sperimentale restituisce `Error` se la verifica fallisce e **non**
esegue automaticamente il bytecode. Un verificatore host separato,
`NailPinnedProviderRebuild.verify`, richiede l'impronta di sorgente e
quella dell'immagine bootstrap ottenute tramite un canale attendibile
indipendente, quindi ricompila in una VM nuova senza grant per confrontare
le firme e il bytecode esattamente. Questo non autentica un publisher
sconosciuto e non concede accesso al linker.

Controlli differenziali e di portabilità:

```sh
haxe seed-image.hxml
haxe nail-typechecker-test-interp.hxml
haxe row-scheme-preview-test-interp.hxml
haxe row-scheme-preview-test-js.hxml && node build/tests/row-scheme-preview.js
haxe row-scheme-preview-test-php.hxml && php build/tests/php-row-scheme-preview/index.php
```

Per il contratto esatto e le limitazioni si veda
[ROW-SCHEME-ABI-PREVIEW.md](./docs/ROW-SCHEME-ABI-PREVIEW.md).
