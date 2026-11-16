# Nail Cookbook — v0.41

[Language tour](./LANGUAGE-TOUR.md) · [Esecuzione JS/PHP/browser](./RUNNING.md) · [indice](./docs/README.md)

Ricette progressive per usare **questa** versione, non le feature delle release successive. Separare gli snippet in file diversi quando ridefiniscono lo stesso nome; leggere sempre i risultati come valori restituiti dalla VM, non come output automatico della pagina web.

## Ricetta 1 — risultato immediato

File pronto: [`examples/cookbook-start.nail`](./examples/cookbook-start.nail).

```nail
def twice x = x * 2 ;
twice 21 ;
```

**Risultato atteso:** `42` come valore dell'espressione. Per usarlo da Node/PHP segui [RUNNING.md](./RUNNING.md).

## Ricetta 2 — trasformare un elenco

```nail
def twice x = x * 2 ;
map twice [ 1 , 2 , 3 ] ;
```

**Risultato atteso:** `[2, 4, 6]`. Per v0.3, carica prima `stdlib.nail`; nelle versioni Haxe chiama `vm.loadStdlib()`.

## Ricetta 3 — Lettura con risultato tipizzato

```nail
def songOrError key =
  match readAsset key with
  | CoreOk contents -> contents
  | CoreErr reason -> reason ;
```

`readAsset` non esiste senza grant host: deve provenire da `NailHost.readTextResult`.

## Ricetta 4 — Scrittura con permessi separati (v0.39)

```nail
def save key contents =
  match writeAsset key contents with
  | CoreOk savedKey -> savedKey
  | CoreErr reason -> reason ;
```

`writeAsset` è importato come `NailHost.writeTextResult`: una firma `Text -> Text -> CoreResult[Text, Text]` più un grant host dedicato. Non è eseguibile direttamente nella demo browser priva di permessi.

Prova i casi `denied`, `too-large` e `quota-exhausted` con `haxe host-text-writes-test-interp.hxml` dopo `haxe seed-image.hxml`. Il test usa uno store in memoria, non scrive file reali. Consulta [la specifica](./HOST-CAPABILITIES.md) prima di implementare una callback.

## Allenamento: studiare l'implementazione

- Trova il percorso dal sorgente al valore usando [README](./README.md) · [SPEC](./SPEC.md) · [casi runtime](./cases.json) · [Main.hx](./src/Main.hx) · [parser Haxe](./src/nail/Parser.hx) · [stdlib.nail](./stdlib.nail).
- Riscrivi l'esempio usando una funzione ausiliaria, poi verifica un caso negativo (nome non definito, tipo incompatibile, pattern non esaustivo quando applicabile).
- Nelle release Haxe, confronta `test-interp.hxml`, `test-js.hxml` e `test-php.hxml`; una build riuscita non prova automaticamente il funzionamento della demo browser.

## Ricetta 5 — Verificare immagini prima di concedere I/O

Nell'applicazione ospite (Haxe), prima di chiamare Nail:

```haxe
var policy = new nail.ModuleImageTrust();
policy.pin('Saver', digestPreapprovato);
var modules = nail.ModuleLinker.linkTrustedImages(
  immaginiCompilate, policy, 25000000, grants);
```

Il digest **non va calcolato all'avvio sulle stesse immagini non attendibili**;
va letto da un manifest di distribuzione protetto e indipendente.
Prova a sostituire un'immagine senza cambiare il manifest: la verifica deve
rifiutarla senza eseguire codice né effettuare I/O. Il test completo è in
`src/TrustedModuleImagesTestMain.hx`.

## Ricetta 6 — Revoca senza ricompilare un modulo

Il codice Nail resta invariato:

```nail
def save key text =
  match writeAsset key text with
  | CoreOk saved -> saved
  | CoreErr reason -> reason ;
```

L'host può revocare dopo il link:

```haxe
var app = nail.ModuleLinker.linkTrustedImages(images, pins, 25000000, grants);
grants.revokeWriteText('Saver');
```

Le chiamate successive di `Saver` ricevono `CoreErr "revoked"` senza
invocare il backend. La revoca di `Saver` non interrompe il permesso
di `OtherSaver`, anche se l'host aveva condiviso lo stesso writer fra moduli.
Se invece l'host chiama `writer.revoke()`, tutti i riferimenti a
**quell'istanza** smettono di funzionare. Nessuna di queste operazioni
ripristina una capability revocata.
