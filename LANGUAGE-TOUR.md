# Nail Language Tour — v0.46

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

## v0.45 — Int, Ratio e Float: linguaggio esplicitamente versionato

Il nuovo sorgente dichiara **la versione del linguaggio**, non il suo
sistema numerico, mediante una vera istruzione (i commenti sono commenti):

```nail
nail 0.45 ;

Div : Int   Int   Ratio ;
Div : Ratio Ratio Ratio ;
Div : Float Float Float ;
Div : Int   Ratio Ratio ;
Div : Ratio Int   Ratio ;

def divide x y : Div = x / y ;

divide 9 2 ;             # Ratio, esatto 9/2
divide 9.0 2.0 ;         # Float 4.5
divide ( toRatio 9 ) 2 ; # Ratio 9/2
1 / 3 + 1 / 6 ;         # Ratio 1/2
0.1 + 0.2 ;             # Float approssimato
```

- `Int`: letterali **senza punto decimale**, interi con precisione
  arbitraria fino al budget di cifre della VM.
- `Ratio`: razionali esatti; `Int / Int` restituisce **sempre** Ratio,
  anche quando il valore matematico è intero.
- `Float`: letterali **con punto decimale**, in virgola mobile binaria.
- `Int + Int`, `Int - Int`, `Int * Int` restituiscono Int.
- `Int` e `Ratio` si possono combinare esattamente, restituendo Ratio.
- `Float` si combina soltanto con `Float`. Nessuna conversione implicita
  da `Int` o `Ratio` a `Float`.
- Conversioni dichiarate: `toRatio : Int -> Ratio`,
  `toFloat : Int|Ratio -> Float`, `ratioFromText : Text -> Ratio`,
  `intFromText : Text -> Int`. `toFloat` può arrotondare.

Le dichiarazioni `Div : T1 T2 TResult ;` sono **relazioni statiche**
ammesse per un insieme chiuso di cinque firme. Sono validate, respingono
duplicati, non creano implementazioni e non compaiono nel bytecode. Se il
file ne dichiara soltanto alcune, il checker permette quelle righe nelle
chiamate alle funzioni annotate `: Div`. Senza dichiarazioni vengono usate
le cinque firme intrinseche.

`def divide x y : Div = x / y ;` abilita il polimorfismo dell'operatore
solo in quella funzione. Senza annotazione l'inferenza di operatori con
argomenti sconosciuti viene rifiutata: **scelta B**, senza overload impliciti.

L'esecuzione produce codifiche distinguibili nei test: `I:n/1` per Int
e `R:n/d` per Ratio; `Float` produce un numero JSON. Queste stringhe
sono l'output diagnostico dell'host, non la sintassi normale dei numeri.

**Limiti di transizione:** le librerie bootstrap storiche senza header
continuano nel vecchio dialetto per non modificare il compilatore scritto
in Nail prima di migrare tutta la stdlib. La v0.45 nuova richiede
`nail 0.45 ;`; non è ancora la modalità predefinita dei sorgenti senza
header. Moduli runtime compilati separatamente e firme `: Div` come
valori di prima classe non sono ancora supportati per il nuovo ABI.
L'API di compilazione pura non sostituisce `TypeChecker.check`.

## v0.46 — Relazioni esplicite Add, Sub, Mul e compatibilità di linguaggio

La dichiarazione di versione resta codice Nail, non un commento:

```nail
nail 0.46 ;

Add : Int Int Int ;
Add : Int Ratio Ratio ;
Add : Float Float Float ;

Sub : Int Int Int ;
Sub : Ratio Int Ratio ;

Mul : Int Int Int ;
Mul : Ratio Ratio Ratio ;

def add x y : Add = x + y ;
def subtract x y : Sub = x - y ;
def multiply x y : Mul = x * y ;

add 1 ( toRatio 2 ) ;
multiply ( 1 / 3 ) ( 3 / 5 ) ;
```

Anche `Div` continua ad accettare cinque combinazioni. Tutte e quattro
le relazioni hanno risultati univoci per una coppia di tipi e un insieme
chiuso di righe supportate. Le dichiarazioni dei singoli file possono
restringere l'insieme delle firme ammesse, non aggiungere implementazioni
né creare conversioni verso Float. L'annotazione `: Add`, `: Sub`,
`: Mul`, `: Div` è **obbligatoria** quando una funzione astrae sui
tipi degli argomenti: nessuna generalizzazione numerica automatica.
Le firme esplicite restano verificabili separatamente per ciascuna riga.

Un runtime v0.46 riconosce anche sorgenti `nail 0.45 ;`, dato che le
regole numeriche precedenti non sono cambiate; un sorgente `nail 0.47 ;`
viene rifiutato. Le nuove relazioni non sono ammesse nei programmi
dichiarati `nail 0.45 ;`.

La libreria standard storica continua ad alimentare il bootstrap di
produzione; un test separato di v0.46 prova a ricompilarla **interamente**
nella nuova semantica e a verificarne il punto fisso. Il vecchio percorso
non sarà eliminato finché tutti i test storici non saranno migrati.
