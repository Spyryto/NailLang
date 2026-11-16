# Nail Language Tour — v0.42

[Versioni](./docs/versions.md) · [Cookbook](./COOKBOOK.md) · [Esecuzione](./RUNNING.md) · [Host capabilities](./HOST-CAPABILITIES.md)

La v0.40 non cambia la grammatica Nail. Aggiunge un confine di **integrità dei moduli compilati**, lato host. La v0.39 aveva introdotto la scrittura controllata; la v0.40 impedisce che un'immagine sostitutiva non autorizzata si presenti con lo stesso nome di un modulo autorizzato.

## Sintassi: funzioni, record, risultati

```nail
def twice x = x * 2 ;
twice 21 ;

type Song { title Text bpm Number } ;
def song = Song " Samba " 96 ;
song . title ;
```

Le funzioni sono currificate, i token vanno separati da spazi, e l'accesso ai record usa `value . field`. Per i fallimenti recuperabili si usa il risultato tipizzato:

```nail
def save key contents =
  match writeAsset key contents with
  | CoreOk savedKey -> savedKey
  | CoreErr reason -> reason ;
```

`writeAsset` è un import concesso dall'host con firma `Text -> Text -> CoreResult[Text, Text]`, non una funzione globale accessibile indiscriminatamente.

## Novità per l'host: pin di integrità SHA-256

```haxe
var pinned = new nail.ModuleImageTrust();
pinned.pin('Saver', digestAffidabileDallaDistribuzione);
var app = nail.ModuleLinker.linkTrustedImages(
  immaginiDaVerificare, pinned, 25000000, grants);
```

Ogni immagine deve essere ammessa tramite digest atteso, ottenuto da una fonte indipendente dalle immagini che verranno caricate. Le immagini vengono verificate **tutte prima** dell'inizializzazione dei moduli o del collegamento delle capability.

**Non confondere digest e firma:** SHA-256 protegge l'integrità rispetto a un riferimento già affidabile; non dimostra chi ha prodotto il modulo. Se viene alterato anche il riferimento affidabile, la verifica non protegge.

## Laboratorio

1. `haxe seed-image.hxml` genera l'immagine di bootstrap.
2. `haxe trusted-module-images-test-interp.hxml` verifica le accettazioni e i rifiuti delle immagini.
3. Ripeti su JavaScript/PHP seguendo [RUNNING.md](./RUNNING.md).
4. Confronta `src/nail/ModuleImageTrust.hx`, `src/nail/ModuleLinker.hx` e [HOST-CAPABILITIES.md](./HOST-CAPABILITIES.md).

Le versioni precedenti restano consultabili tramite tag. L'API JS continua a esportare `NailSeed` per compatibilità.

## Novità v0.41: revoca dei permessi da parte dell'host

Non cambia la sintassi Nail. Il codice `readAsset key` oppure
`writeAsset key contents` usa le funzioni che il processo host gli ha
passato. Dopo la revoca, una chiamata restituisce `CoreErr " revoked "`
(oppure `{ok:false, error:"revoked", value:""}` nell'API legacy).

```haxe
// Anche i moduli già inizializzati osservano questa revoca.
grants.revokeWriteText('Saver');
grants.revokeReadText('Viewer');

// Per revocare un oggetto condiviso fra più moduli:
writer.revoke();
```

Le funzioni scriventi già applicate al primo argomento non bypassano la
revoca: il controllo si ripete al secondo argomento, prima della callback.
L'operazione è irreversibile per quel grant/oggetto. Le chiamate già dentro
una callback host sincrona non possono essere annullate retroattivamente.

Esegui `haxe revocable-capabilities-test-interp.hxml` e i target JS/PHP
descritti in [RUNNING.md](./RUNNING.md).

## v0.42 — Manifest firmati (lato host)

Nail non cambia grammatica: i moduli continuano a usare le stesse funzioni,
i record e gli import di v0.41. Ora l'host può autorizzare una **distribuzione
firmata Ed25519** invece di gestire a mano tutti i digest SHA-256.

```haxe
var policy = new nail.ModuleSigningPolicy('v0.42');
policy.trustKey('publisher-2026', chiavePubblicaAffidabile);
var app = nail.ModuleLinker.linkSignedImages(
  immagini, manifestoFirmato, policy, 25000000, grants);
```

La firma copre versione attesa, identificativo chiave e lista ordinata dei
moduli e dei loro SHA-256. L'host sceglie preventivamente quali chiavi e
versioni accettare, senza consultare il manifesto non attendibile.

Node.js usa `node:crypto`, PHP usa `sodium`. Un browser o l'interprete
Haxe richiedono invece un verificatore sincrono affidabile fornito
dall'applicazione; altrimenti la verifica fallisce. I test reali includono
manomissione, chiavi sconosciute, cambio versione e sostituzione di moduli.

Approfondisci [HOST-CAPABILITIES.md](./HOST-CAPABILITIES.md).
