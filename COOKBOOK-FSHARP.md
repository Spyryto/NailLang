# Nail × F# — cookbook e confronto evolutivo

[Cookbook Dart](COOKBOOK-DART.md) · [Cookbook Nail](COOKBOOK.md) · [Lookbook](LOOKBOOK.md) · [Decisioni](DECISIONS.md) · [Esecuzione](RUNNING.md)

Riferimenti: [Tour of F#](https://learn.microsoft.com/en-us/dotnet/fsharp/tour), [Language Reference](https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/). Gli esempi F# sono originali.

**Baseline:** esempi Nail nel dialetto 0.49 documentato nel cookbook Dart, più import documentati dalla 0.54 e stato della release v0.60 pubblicata. Non si presume che gli header storici restino accettati dal runtime futuro. Usare la toolchain corrispondente; verificare separatamente l'esecuzione sul candidato. Gli snippet sono ricavati o adattati da sintassi già documentata nel repo, ma non sono stati eseguiti durante questa redazione. Ogni snippet è indipendente; caricare la stdlib Nail per le ricette che la usano. Il risultato Nail è un valore della VM, non una stampa implicita.

## 1. Binding, funzioni e applicazione parziale

F#:
```fsharp
let add x y = x + y
let increment = add 1
increment 41 // 42
```

Nail:
```nail
nail 0.49 ;
def add x y = x + y ;
def increment = add 1 ;
increment 41 ;
```

Entrambi: binding immutabili per default, funzioni currificate, applicazione parziale ordinaria. Le funzioni Nail annotate con relazioni numeriche finite hanno invece restrizioni specifiche.

## 2. Polimorfismo e inferenza

F#:
```fsharp
let identity x = x
identity 42
identity true
```

Nail:
```nail
nail 0.49 ;
def identity x = x ;
identity 42 ;
identity true ;
```

La funzione identità ha tipo generico. Nail usa inferenza HM e vincoli espliciti in casi specifici. Non equivalgono all'intero sistema F#, con sottotipi .NET, overload e SRTP.

## 3. Map, filter e fold

F#:
```fsharp
[1; 2; 3; 4]
|> List.filter (fun x -> x > 2)
|> List.map (fun x -> x * 2)
|> List.fold (+) 0 // 14
```

Nail:
```nail
nail 0.49 ;
fold ( fun acc x -> acc + x ) 0
  ( map ( fun x -> x * 2 )
    ( filter ( fun x -> x > 2 ) [ 1 , 2 , 3 , 4 ] ) ) ;
```

Il calcolo è lo stesso; la pipeline F# è particolarmente leggibile. Valutare l'ergonomia di pipeline e composizione in Nail prima di introdurre nuovi operatori o sintassi.

## 4. Ricorsione

F#:
```fsharp
let rec sum acc n =
    if n <= 0 then acc
    else sum (acc + n) (n - 1)
sum 0 5 // 15
```

Nail:
```nail
nail 0.49 ;
def sum acc n =
  if n <= 0 then acc
  else sum ( acc + n ) ( n - 1 ) ;
sum 0 5 ;
```

La forma è ricorsiva di coda. Nail 0.60 rappresenta le posizioni di coda nella CoreIR; questo non basta a garantire TCO per ogni backend. Misurare stack, allocazioni e tempi prima di fare affermazioni prestazionali.

## 5. Record

F#:
```fsharp
type Lesson = { Hours: int; Rate: int }
let lesson = { Hours = 2; Rate = 30 }
lesson.Hours * lesson.Rate // 60
```

Nail:
```nail
nail 0.49 ;
type Lesson { hours Int rate Int } ;
def lesson = Lesson 2 30 ;
( lesson . hours ) * ( lesson . rate ) ;
```

F# offre inizializzazione per nome, aggiornamento non distruttivo e record anonimi. Nail documenta record nominali e strutturali; verificare separatamente le operazioni e le garanzie, senza dedurre equivalenza completa.

## 6. Discriminated union e pattern matching

F#:
```fsharp
type Answer = Missing | Found of int
let getOr fallback answer =
    match answer with
    | Missing -> fallback
    | Found n -> n
getOr 0 (Found 42)
```

Nail:
```nail
nail 0.49 ;
type Answer = Missing | Found Int ;
def getOr fallback = function
  | Missing -> fallback
  | Found n -> n ;
getOr 0 ( Found 42 ) ;
```

Nucleo concettualmente vicino. Nail offre ADT e pattern matching; le forme di pattern F# più ricche (guardie, active patterns, ecc.) vanno confrontate individualmente. Option e Result sono tipi di libreria in F#; Nail permette ADT analoghi e ha CoreResult per contratti host.

## 7. Numeri: una differenza intenzionale

F#:
```fsharp
let bpm = 97
60 / bpm          // 0, divisione intera
60.0 / float bpm  // approssimazione Float
```

Nail:
```nail
nail 0.49 ;
def bpm = 97 ;
60 / bpm ;             # Ratio 60/97
toFloat ( 60 / bpm ) ;  # approssimazione esplicita
```

Nail non deve imitare F# quando una propria semantica è desiderabile. Le relazioni finite Nail non sono SRTP F#; confrontare il costo delle dichiarazioni e le garanzie offerte.

## 8. Moduli e locality of behavior

F#:
```fsharp
module Math =
    let twice x = x * 2
Math.twice 21
```

Nail (0.54, due sorgenti compilati come moduli con interfacce esplicite):
```nail
nail 0.54 ;
def twice x = x * 2 ;
```

```nail
nail 0.54 ;
def answer x = twice x ;
import twice from Math ;
```

L'host deve registrare il provider Math, esportare twice e fornire la dipendenza al consumer. Non è un programma unico eseguibile direttamente nella CLI. Vedi [test degli import](src/ModuleSourceImportsTestMain.hx). F# usa moduli, namespace e open; Nail privilegia import selettivi e contesti espliciti. Il generale use Module non è ancora una feature pubblica.

## 9. Lookbook F# — mappa delle differenze

| Area F# | Nail: stato documentato | Domanda da porre |
|---|---|---|
| Funzioni, curry, closure, HM | Nucleo presente | Possiamo ridurre annotazioni e codice? |
| List.map/filter/fold, pipeline, composizione | Operazioni pure presenti; ergonomia pipeline da verificare | Una funzione di libreria basta? |
| Record, DU, Option, Result | ADT e record presenti; equivalenze parziali | Quali operazioni mancano nell'uso reale? |
| Pattern matching, active patterns | Match su ADT/liste; active patterns non documentati | Si compone con funzioni e ADT? |
| Tuple, sequence, array, collection expressions | Liste e vettori presenti; non assumere equivalenza per tuple, lazy sequence e comprehension | Quali strutture servono davvero? |
| Generics, equality, SRTP | HM, Eq e relazioni finite; non equivalenti agli SRTP | La soluzione Nail è più semplice o più limitata? |
| Record aperti / vincoli strutturali | Preview HM open-row nella release v0.60, non ABI pubblico | Come mantenere semplicità e sicurezza? |
| Computation expressions (async/task/seq/custom) | Nessun equivalente generale documentato | Servono builder, trasformatori AST o funzioni ordinarie? |
| Async, task e parallelismo | Obiettivo; nessun equivalente generale nel linguaggio documentato | Come sfruttare gli host senza complessità gratuita? |
| Units of measure | Non documentate come feature Nail | Esiste un caso reale per vincoli dimensionali? |
| Quotations / metaprogrammazione | AST e trasformatori, macro; non equivalenti alle quotations tipizzate | Quanto codice si può esprimere con il nucleo? |
| Interoperabilità .NET, OO, type providers | Modello diverso: host JS/PHP e capability esplicite | Quale interoperabilità serve ai nostri casi d'uso? |
| MVU (ecosistema Elmish) | Obiettivo applicativo, non framework integrato | Quanto poco codice serve per una UI reale? |

Per approfondire: [computation expressions](https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/computation-expressions), [active patterns](https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/active-patterns), [units of measure](https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/units-of-measure).

## 10. Aggiornamento continuo

Per ogni modifica significativa a sintassi, tipi, stdlib, moduli, effetti o metaprogrammazione:
- aggiornare le ricette e le righe interessate di questo confronto e del confronto Dart; se nessuna è interessata indicarlo nelle note della modifica quando pertinente;
- indicare versione Nail effettivamente verificata, eventuale percorso sperimentale/host, risultato atteso e test o comando di riproduzione;
- separare equivalenza semantica, alternativa componibile, parziale/host e feature mancante; non inventare sintassi Nail;
- confrontare espressività, tipi, leggibilità e complessità di implementazione; distinguere prestazioni misurate da ipotesi;
- conservare lo storico tramite tag Git; non riscrivere le feature di una versione passata;
- se una differenza suggerisce una nuova feature, registrarla come proposta in DECISIONS o ROADMAP, senza cambiare automaticamente le priorità.

F# è un riferimento funzionale, Dart un riferimento pratico complementare. Non è un obiettivo clonare entrambi: Nail può scegliere soluzioni diverse e più semplici.
