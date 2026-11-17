# Nail Cookbook — v0.49

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

## Ricetta 7 — Caricare una distribuzione firmata

Nel programma host, NON nel codice Nail:

```haxe
var policy = new nail.ModuleSigningPolicy('v0.42');
policy.trustKey('publisher-2026', publicKeyBase64DaConfigAffidabile);
var modules = nail.ModuleLinker.linkSignedImages(
  moduleImages, signedManifestJson, policy, 25000000, grants);
```

Prima di distribuire i moduli, l'autore deve firmare con Ed25519 il
contenuto di `SignedModuleManifest.canonicalPayload`. Nel repository
non è inclusa alcuna chiave privata di produzione. L'host non deve mai
fidarsi della chiave pubblica trovata nello stesso bundle non attendibile.

Per fare pratica guarda `src/SignedManifestsTestMain.hx`: il seed
Ed25519 del test è pubblicato intenzionalmente e **non deve essere
usato per distribuzioni reali**.

## Ricetta 8 — Quantizzare una durata musicale esatta

Per convertire una durata esatta in un numero intero di battiti o tick
senza introdurre errori di virgola mobile:

```nail
# nail: 0.29

def barsToBeats bars = bars * 4 ;
def nearestTick beats ticksPerBeat =
  exactRoundEven ( beats * ticksPerBeat ) ;

nearestTick ( 1 / 3 ) 960 ;  # Exact 320
nearestTick ( 1 / 4 ) 960 ;  # Exact 240
nearestTick ( 1 / 2 ) 3 ;    # Exact 2 (1.5, ties-to-even)
```

La quantizzazione è un'operazione **esplicita**: prima della chiamata
`exactRoundEven`, il risultato può ancora essere una frazione esatta.
Per la durata di una battuta puoi mantenere i razionali e arrotondare
soltanto nel passaggio finale verso una griglia con tick interi.

```nail
# nail: 0.29
def wholeBeats beats = exactFloor beats ;
def isWholeBeat beats = exactIsInteger beats ;
wholeBeats ( -7 / 3 ) ;  # -3
isWholeBeat ( 8 / 2 ) ;  # true
```

Questo evita sia troncamenti impliciti sia la perdita di precisione con
numeri molto grandi.

## Ricetta 9 — Vincolo esplicito `: Div`

```nail
def divide x y : Div = x / y ;
divide 9 2 ;
divide ( exactFromText " 3 " ) ( exactFromText " 2 " ) ;
```

La firma stampata dal checker è
`Div a b c => a -> b -> c`. L'annotazione è **obbligatoria** per
abilitare questo primo overload: `def divide x y = x / y` non
generalizza automaticamente il vincolo. Gli argomenti devono
avere tipi corrispondenti alla stessa riga della tabella interna;
l'uso misto richiede conversione esplicita.

Nota: queste firme usano ancora i due domini numerici esistenti,
`Number` e `Exact`; `Int`, `Ratio`, `Float` e
le dichiarazioni sorgente `Div : ...` sono da implementare.

## Ricetta 10 — Battiti esatti e risultato Float esplicito

```nail
nail 0.45 ;

def beatsPerBar = 4 ;
def tempoBpm = 97 ;
def secondsPerBeat = 60 / tempoBpm ;
def secondsPerBar = beatsPerBar * secondsPerBeat ;

secondsPerBar ;          # Ratio 240/97
toFloat secondsPerBar ;  # Float, conversione esplicita
```

Per scrivere una funzione di divisione con cinque combinazioni esatte e
floating point:

```nail
nail 0.45 ;
Div : Int Int Ratio ;
Div : Ratio Ratio Ratio ;
Div : Float Float Float ;
Div : Int Ratio Ratio ;
Div : Ratio Int Ratio ;
def divide x y : Div = x / y ;
```

## Ricetta 11 — Funzioni aritmetiche con firme multiple, una sola implementazione

```nail
nail 0.46 ;
Add : Int Int Int ;
Add : Int Ratio Ratio ;
Add : Float Float Float ;
def add x y : Add = x + y ;
add 2 3 ;                 # Int 5
add 2 ( 1 / 2 ) ;         # Ratio 5/2
add 2.0 3.0 ;             # Float 5
```

La tabella `Add` definisce una relazione fra due tipi di input e il
tipo di output, non un elenco di clausole runtime in stile Elixir.
Se si elimina `: Add` dalla definizione, Nail **non** generalizza
automaticamente il polimorfismo dell'operatore.

## Ricetta 12 — Una frazione esatta nel runtime distribuito

```nail
nail 0.47 ;
def bpm = 97 ;
def secondsPerBeat = 60 / bpm ;
secondsPerBeat ;              # Ratio 60/97
toFloat secondsPerBeat ;      # Float approssimato, esplicitamente
```

Il runtime bootstrap distribuito usa il compilatore scritto in Nail,
già compilato con `Int` e `Ratio`. È indipendente dal parser sorgente
Haxe, a differenza della distribuzione standard della VM completa.

## Ricetta 13 — Tempo musicale esatto fra moduli

Il modulo **Tempo** esporta il rapporto esatto:

```nail
nail 0.48 ;
def secondsPerBeat = 60 / 97 ;
```

Il manifesto host esporta `secondsPerBeat : Ratio`. Il modulo
**Phrase** importa quel simbolo come `tempo_secondsPerBeat : Ratio`:

```nail
nail 0.48 ;
def twoBeats = tempo_secondsPerBeat * 2 ;
```

Il risultato è ancora `Ratio`, senza arrotondamenti. La compilazione
separata usa `ModuleLinker.compileInferred` e
`ModuleImage.encode`; poi `ModuleLinker.linkImages` carica soltanto i
due JSON, senza leggere sorgenti Nail o eseguire il type checker.


## Ricetta 14 — Un unico algoritmo con firme unarie e ternarie (v0.49)

```nail
nail 0.49 ;
Scale : Int Int ;
Scale : Ratio Ratio ;
Scale : Float Float ;
Mix : Int Int Int Int ;
Mix : Float Float Float Float ;

def scale x : Scale = x * x ;
def mix a b c : Mix = a * b + c ;

scale 3 ;           # Int 9
scale ( 1 / 2 ) ;   # Ratio 1/4
mix 2 3 4 ;        # Int 10
mix 2.0 3.0 4.0 ;  # Float 10.0
```

La forma `Scale : Int Int` indica **un argomento Int e un risultato Int**. Nella firma `Mix : Int Int Int Int` gli argomenti sono tre, l'ultimo `Int` è il risultato. È vietato associare alla stessa tupla degli argomenti due risultati diversi. Il corpo resta uno solo, convalido per tutte le righe. La chiamata a una funzione vincolata deve essere completa, non `mix 2`; non vengono aggiunte conversioni implicite né inferenza automatica dei sovraccarichi.

Per condividere `scale` fra moduli, il provider la esporta tramite `ModuleLinker.compilePublic` e il client passa lo stesso `RelationContract` nel manifesto di import. Il formato JSON v3 conserva le righe e permette al linker di controllare il contratto senza rileggere il sorgente Nail.

## Ricetta 15 — Importare una macro con tipi numerici coerenti (v0.49)

La macro vive in [`examples/macros/numbers.nail`](./examples/macros/numbers.nail):

```nail
nail 0.49 ;
macro next x = quote ( unquote x + 1 ) ;
export next ;
```

Il programma [`examples/macro-next-049.nail`](./examples/macro-next-049.nail)
può importarla:

```nail
nail 0.49 ;
import next from numbers ;
expand next 41 ;
```

Il risultato è `I:42/1` (tipo `Int`). Dopo aver compilato il
runtime source-free PHP, esegui dalla radice del repository:

```sh
php build/boot/php/index.php --macro-dir examples/macros examples/macro-next-049.nail
```

Il modulo deve dichiarare **la stessa versione `nail 0.49 ;` del
programma**: la dichiarazione mancante o una versione diversa producono
un errore esplicito. Vale anche per gli import indiretti. Per i vecchi
programmi senza header, le macro importate devono essere senza header;
l'esperimento Exact con `# nail: 0.29` è separato da Float.
