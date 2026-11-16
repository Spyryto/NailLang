# Nail Language Tour — v0.40

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
