# Nail Language Tour — v0.44

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

## v0.43 — Arrotondare i razionali senza perdere precisione

Nail possiede due domini numerici intenzionalmente separati: il vecchio
`Number` (Float binario) e il tipo `Exact`, attivato esplicitamente con
`# nail: 0.29`. La v0.43 **non introduce un nuovo dialetto**: arricchisce
`Exact` con operazioni pure e tipizzate, senza conversione implicita.

```nail
# nail: 0.29

exactFloor ( 7 / 3 ) ;       # 2
exactCeil ( -7 / 3 ) ;       # -2
exactTruncate ( -7 / 3 ) ;   # -2
exactRoundEven ( 5 / 2 ) ;   # 2
exactRoundEven ( 7 / 2 ) ;   # 4
exactIsInteger ( 8 / 4 ) ;   # true
exactIsInteger ( 5 / 2 ) ;   # false
```

- `exactFloor : Exact -> Exact` arrotonda verso meno infinito.
- `exactCeil : Exact -> Exact` arrotonda verso più infinito.
- `exactTruncate : Exact -> Exact` arrotonda verso zero.
- `exactRoundEven : Exact -> Exact` arrotonda al più vicino;
  esattamente a metà sceglie il numero pari (ties-to-even).
- `exactIsInteger : Exact -> Bool` controlla se il denominatore ridotto è 1.

I risultati restano di tipo `Exact` anche quando sono numeri interi; non
creiamo un finto nuovo tipo `Int`. Il type checker rifiuta `exactFloor 1`
nel dialetto Float perché non applica conversioni implicite. Per passare
testo numerico a Exact c'è `exactFromText`.

L'implementazione usa divisione euclidea su naturali arbitrariamente grandi
e conserva i budget di cifre dell'aritmetica esatta; **nessun Float**
intermedio e nessuna variazione del bytecode. Esempi eseguibili in
`src/ExactRoundingTestMain.hx` e [COOKBOOK.md](./COOKBOOK.md).

## v0.44 — Polimorfismo numerico **solo su dichiarazione esplicita**

Questa versione introduce il **primo passo verificabile** verso le
relazioni di tipo, seguendo la regola B: gli operatori sovraccaricati
non diventano automaticamente polimorfici in una funzione.

```nail
def divide x y : Div = x / y ;

divide 9 2 ;
divide ( exactFromText " 3 " ) ( exactFromText " 2 " ) ;
```

La forma `def divide x y : Div = x / y ;` definisce normalmente i due
parametri *di valore* `x` e `y`; `: Div` è solo una dichiarazione di
vincolo che la verifica statica interpreta. Non crea parametri, non
converte numeri e **non aggiunge istruzioni bytecode**.

In questa prima iterazione, le sole firme reali disponibili sono:

```text
Div : Number Number Number
Div : Exact  Exact  Exact
```

Sono righe **illustrative della tabella interna**, non ancora dichiarazioni
sorgente accettate dal parser. `Number` è il Float storico, `Exact`
è il razionale storico. L'obiettivo successivo resta la tabella richiesta
`Div : Int Int Ratio`, `Div : Ratio Ratio Ratio`,
`Div : Float Float Float`, con tipi numerici indipendenti.

Per applicare l'operatore a entrambi i domini, il risultato usa il
tipo determinato dalla riga corrispondente. Non esiste una coercizione
implicita fra `Number` e `Exact`. Senza `: Div`, la funzione
rimane monomorfica secondo il checker attuale.

**Limiti intenzionali di v0.44:** soltanto `Div`, soltanto definizioni
con due parametri, chiamate dirette completamente applicate
(`divide x y`); non `divide`, `divide x`, passaggio come funzione
di ordine superiore, esportazione di firme relazionali fra moduli
o annotazione di funzioni nel dialetto sorgente `# nail: 0.29`.
Questi casi sono rifiutati dal checker, non emulati in modo insicuro.
La VM conserva il normale runtime dinamico dei valori, mentre i
vincoli sono controllati **solo quando si usa il TypeChecker**.

Per i programmi nel dialetto Float, creare un valore razionale resta
possibile tramite `exactFromText`. Non si tratta ancora del redesign
`Int / Ratio / Float`.

```sh
haxe seed-image.hxml
haxe explicit-relations-test-interp.hxml
haxe explicit-relations-test-js.hxml && node build/tests/explicit-relations.js
haxe explicit-relations-test-php.hxml && php build/tests/php-explicit-relations/index.php
```
