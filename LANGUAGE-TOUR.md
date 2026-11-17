# Nail Language Tour — v0.53

[Versioni](./docs/versions.md) · [Cookbook](./COOKBOOK.md) · [Esecuzione](./RUNNING.md) · [Host capabilities](./HOST-CAPABILITIES.md) · [Cookbook Dart → Nail](./COOKBOOK-DART.md) · [Lookbook](./LOOKBOOK.md)

La v0.40 non cambia la grammatica Nail. Aggiunge un confine di **integrità dei moduli compilati**, lato host. La v0.39 aveva introdotto la scrittura controllata; la v0.40 impedisce che un'immagine sostitutiva non autorizzata si presenti con lo stesso nome di un modulo autorizzato.

## Consolidamento ABI nel ramo corrente

I moduli numerici moderni vengono emessi esclusivamente in
`nailseed.runtime-module.v3`, anche quando non esportano vincoli.
`relationAbi` dichiara la capacità di trasportare relazioni finite;
le righe restano facoltative. Le immagini legacy v1 rimangono separate.
I vecchi artefatti moderni v2 vanno utilizzati con la rispettiva
release storica, non decodificati dal nuovo runtime. Questo non cambia
l'ABI numerico `int-ratio-float.v1` né il formato delle immagini bootstrap.

## Novità v0.50 — Analisi strutturata del sorgente

NailLang espone un'API **per strumenti di sviluppo**, indipendente da VS Code o
da un Language Server. `SourceAnalysis.analyze(source)` restituisce
`diagnostics`, `symbols`, `references` ed `evaluations` con tipi
inferiti e coordinate del sorgente. Non esegue il programma.

```js
const { NailSeed } = require('./build/js/nailseed.js');
const report = NailSeed.analyze('nail 0.50 ; def id x = x ; id 42 ;');
console.log(report.ok, report.evaluations);
```

I riferimenti identificano i binding senza rinominare il codice;
gli errori di tipo sono associati al form originale e le posizioni non
conosciute rimangono `null`. Sono supportati i vincoli della 0.49.
La diagnostica completa, i limiti e i comandi sono in
[Analisi statica](./docs/ANALYSIS.md). Il protocollo LSP è rimandato.

## Novità v0.49 — Vincoli per funzioni di qualunque arità (1–16)

La relazione elenca **i tipi di tutti i parametri**, seguiti dal **tipo di ritorno**. Ogni riga deve avere la stessa arità e a una stessa tupla di parametri non possono corrispondere risultati differenti.

```nail
nail 0.49 ;
Square : Int Int ;
Square : Ratio Ratio ;
Square : Float Float ;
Blend : Int Int Int Int ;
Blend : Float Float Float Float ;
Echo : Text Text ;
Echo : Bool Bool ;

def square x : Square = x * x ;
def blend a b c : Blend = a * b + c ;
def echo x : Echo = x ;

square 4 ;          # Int 16
square ( 1 / 2 ) ;  # Ratio 1/4
blend 2 3 4 ;      # Int 10
echo " ciao " ;     # Text
```

`def blend a b c : Blend` indica **tre parametri reali**, non un tipo speciale per la funzione: la riga `Blend : Int Int Int Int` associa a quei tre `Int` un risultato `Int`. Per un vincolo con `n` parametri servono esattamente `n+1` tipi, perché l'ultimo è l'output. Non servono dichiarazioni di classi, metodi runtime o conversioni automatiche.

Il checker verifica **il medesimo corpo** di una funzione per ogni riga concreta e risolve le chiamate tramite tutti i tipi degli argomenti. L'annotazione `: Square` è esplicita (scelta B): togliendola, non viene inferito automaticamente il polimorfismo degli operatori numerici. Le chiamate vincolate devono essere dirette e completamente applicate: applicazione parziale e passaggio della funzione sovraccarica come valore restano esclusi.

### Esportazione e importazione fra moduli (v0.49)

Il manifesto host `ModuleLinker.compilePublic` può esportare una funzione con `: Square` e importarla in un altro modulo fornendo il corrispondente `RelationContract`. Ogni firma e ogni riga di tipo sono conservate nel formato `nailseed.runtime-module.v3`, insieme a `relationAbi: "finite-relations.v1"`. Al link le firme canoniche devono essere identiche; un modulo v2 senza vincoli resta compatibile con il nuovo linker. Il modulo compilato non richiede sorgente né inferenza al caricamento. Il formato v3 non implementa *typeclass*, coercizioni o vincoli di ordine superiore.


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

## v0.47 — Il compilatore distribuito usa finalmente Int, Ratio e Float

La stdlib e il compilatore scritti in Nail vengono ora **compilati per
la distribuzione con le regole di `nail 0.47 ;`**, non con le regole
predefinite del vecchio `Number`. Un'immagine bootstrap dedicata
contiene il compilatore che sa rigenerare sé stesso, senza richiamare il
parser Haxe a runtime.

```nail
nail 0.47 ;
Div : Int Int Ratio ;
Add : Int Int Int ;
def divide x y : Div = x / y ;
def add x y : Add = x + y ;
divide 3 2 ;
add 1 2 ;
```

Sono ancora accettati i sorgenti dichiarati `nail 0.45 ;` e
`nail 0.46 ;`, che hanno semantiche compatibili. La VM rifiuta una
versione futura non supportata. **I tipi numerici e il versionamento
dell'immagine sono due dimensioni diverse:** la nuova immagine ha formato
`nailseed.postfix-image.v2`, distinto dall'immagine precedente.

La rimozione definitiva del supporto non versionato è un passo
successivo: alcuni test e moduli storici usano ancora gli operatori
`Number`/`Exact`. La stdlib di produzione non dipende più dalla
compilazione con quei tipi, ma i percorsi di compatibilità non sono
ancora tutti rimossi dal runtime. L'API `BootRuntime.compile` non
sostituisce il controllo statico tramite `TypeChecker.check`.

## v0.48 — ABI numerico dei moduli compilati separatamente

I programmi `nail 0.48 ;` condividono la stessa semantica numerica
delle versioni 0.45, 0.46 e 0.47. La novità è che ora è possibile
**compilare e collegare moduli indipendenti** con tipi pubblici
`Int`, `Ratio` e `Float`, senza convertirli in `Number`/`Exact`.

Due moduli, compilati senza conoscere il codice sorgente dell'altro:

```nail
nail 0.48 ;
def beats = 4 ;
def quarter = 1 / 4 ;
def gain = 0.75 ;
```

Il manifesto della libreria dichiara gli export
`beats : Int`, `quarter : Ratio` e `gain : Float`.
Un altro modulo può importarli tramite un manifesto di tipi Haxe:

```nail
nail 0.48 ;
def bars = importedBeats + 4 ;
def half = importedQuarter + ( 1 / 4 ) ;
def louder = importedGain * 2.0 ;
```

Le importazioni, come nella precedente ABI, sono deliberate e autorizzate
dall'host: non esiste importazione implicita di simboli globali.
Il linker verifica **l'identità di ogni firma** e impedisce il
collegamento fra un modulo con ABI legacy e uno con ABI moderna.

Le immagini dei moduli nuovi usano `nailseed.runtime-module.v2`,
`numericAbi: "int-ratio-float.v1"`, `sourceVersion: "0.48"`
e contengono bytecode con rappresentazione esatta (`Int`, `Ratio`).
**Il numero della versione del sorgente non è quello dell'ABI numerico.**
Anche un modulo scritto con `nail 0.45 ;` può quindi essere collegato
a uno con `nail 0.48 ;`, purché entrambi abbiano lo stesso ABI numerico.

Una tabella di relazioni `Add`/`Sub`/`Mul`/`Div` continua a
essere dichiarativa e locale al sorgente. **Nella v0.48** l'export di funzioni con `: Add` era ancora rifiutato; dalla v0.49 è possibile esportarle con un manifesto relazionale esplicito in formato v3. Il passaggio come valore di prima classe rimane non supportato. Rimane inoltre
l'obbligo di chiamare `TypeChecker.check` se si desiderano controlli
statici prima dell'esecuzione di bytecode già compilato.

Le immagini `runtime-module.v1` storiche sono ancora decodificabili
per compatibilità, ma i loro tipi numerici non possono entrare in un
modulo moderno attraverso un import.


## v0.51 — Funzioni dell'host e costruttori Result brevi

L'host può ora concedere a un modulo funzioni sincrone tipizzate con
`HostTextGrants.grantFunction`. I manifest `NailHost` già esistenti
forniscono il nome e la firma. La VM controlla gli argomenti e i
risultati e gestisce revoca e quota di chiamate. Non ci sono import
ambientali, accesso diretto alle API JavaScript/PHP o nuove istruzioni VM.

```nail
nail 0.51 ;
def greeting name =
  match hostGreet name with
  | Ok message -> message
  | Error reason -> reason ;
```

`Ok` e `Error` sono alias dei costruttori storici `CoreOk` e
`CoreErr`. Il tipo resta `CoreResult[A, B]`; anche i predicati e
gli accessor brevi (`Ok?`, `Error?`, `Ok.0`, `Error.0`) sono
disponibili.

I nomi brevi sono oggi predefiniti nello scope globale: definire un
costruttore utente chiamato `Ok` o `Error` nello stesso scope produce
una collisione. Un binding locale come `let Ok = CoreOk in Ok " pronto "`
è valido; tuttavia i pattern `match` risolvono costruttori nominali e
non seguono alias arbitrari di valore. Un futuro import contestuale
potrà rendere opzionale la visibilità di questi nomi senza modificare
l'identità interna `CoreResult`.

L'host deve fornire la funzione e l'autorizzazione
esplicitamente; senza grant il collegamento del modulo non riesce.
Consultare `HOST-CAPABILITIES.md`.


## v0.52 — Liste immutabili nell'FFI tipizzata

Le funzioni concesse dall'host accettano e restituiscono ora anche
`List[T]`, con `T` atomico o a sua volta lista; il payload di
`CoreResult[A, B]` può contenere liste. Non cambia la sintassi Nail:
lo stesso manifesto esplicito `NailHost` della 0.51 fornisce
nome e tipo alla compilazione del modulo.

```nail
nail 0.52 ;
def firstResult key =
  match readMany key with
  | Ok items -> head items
  | Error reason -> reason ;
```

Il programma ha bisogno di un import esplicito `readMany` con tipo
`Text -> CoreResult[List[Text], Text]` e della relativa autorizzazione
dell'host. Una lista è una sequenza immutabile di celle `Cons`/`Nil`:
non viene esposto un array JavaScript/PHP modificabile.

Il runtime valida ogni elemento e ogni coda; valori malformati sono rifiutati
prima di invocare il callback o prima di consegnare il suo risultato.
La profondità massima è 8 e il limite di nodi visitati è 4096
(per una lista piatta vengono contati anche le celle e i valori).
`Vector`, record e oggetti arbitrari non fanno ancora parte di questo FFI.
Consulta [HOST-CAPABILITIES.md](./HOST-CAPABILITIES.md).


## v0.53 — Import runtime dell'host, dichiarati nel sorgente

I moduli compilati separatamente possono dichiarare le dipendenze
`NailHost` senza ripetere i tipi nel manifesto Haxe.
La dichiarazione può stare anche **dopo** la funzione che la utilizza:
è valida per tutto il modulo (non è un import sequenziale).

```nail
nail 0.53 ;
def first key =
  match readMany key with
  | Ok items -> head items
  | Error reason -> reason ;

import fetchMany as readMany from NailHost :
  Text -> CoreResult [ List [ Text ] , Text ] ;
```

La sintassi `as readMany` è facoltativa; omettendola il simbolo
locale si chiama `fetchMany`. Le firme ammesse sono monomorfe:
`Text`, `Bool`, `Int`, `Ratio`, `Float`,
`List [ T ]`, `CoreResult [ A , B ]` e frecce currificate
`T -> U`; i valori sono ancora sottoposti ai limiti dell'FFI 0.52.

Questa dichiarazione funziona **solo** quando il sorgente passa per
`ModuleLinker.compilePublic`, nel quale si può omettere la proprietà
`imports`. L'import viene trasformato nel manifesto tipizzato già
esistente; l'host deve continuare a concedere esplicitamente
`grantFunction`. La VM non ottiene accesso ambientale a JS/PHP.

L'implementazione elimina la dichiarazione prima di compilare,
sostituendola con spazi e mantenendo intatte le interruzioni di riga.
Il compilatore Haxe e quello scritto in Nail ricevono esattamente
lo stesso sorgente normalizzato, senza nuove istruzioni VM.

Gli import di macro `import next from numbers ;` non cambiano.
Gli import runtime di altri moduli Nail e la forma `use Module { ... }`
non sono ancora implementati; meritano una progettazione separata
per non sovrapporre i due meccanismi.
