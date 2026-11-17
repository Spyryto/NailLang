# Nail Lookbook — ciò che manca, ciò che si compone (v0.49)

[Confronto guidato Dart → Nail](./COOKBOOK-DART.md) · [Cookbook generale](./COOKBOOK.md) · [Language Tour Nail](./LANGUAGE-TOUR.md) · [Specifica](./SPEC.md)

Il **lookbook** è il complemento del cookbook: parte da una domanda pratica (*«come faccio un ciclo?»*) o da una feature conosciuta in Dart e chiarisce se la stessa capacità esiste in Nail 0.49. Riferimento esterno: [Dart language](https://dart.dev/language). Non è una promessa di implementare tutte le feature Dart, né una roadmap approvata.

## Legenda

- **Componibile**: mancano una keyword o una comodità, ma il calcolo è già esprimibile in Nail senza estensioni.
- **Parziale / host**: alcune semantiche sono implementabili, ma servono codice host, manifesti, permessi o ci sono limitazioni rilevanti.
- **Assente**: non esiste un equivalente con le stesse garanzie e semantica; un esempio soltanto descrittivo **non** è codice Nail.
- **Alternativa diversa**: una scelta funzionale può risolvere il problema, senza imitare la feature Dart.

Le priorità alla fine sono **ipotesi di utilità per l'ergonomia e il dogfooding**, non variazioni automatiche della roadmap.

## 1. Flusso di controllo

### `for (i = 0; i < n; i++)`

**Stato: Componibile; sintassi assente.** Il caso puro si esprime per ricorsione:

```nail
nail 0.49 ;
def range start stop =
  if start > stop then []
  else cons start ( range ( start + 1 ) stop ) ;
range 1 5 ; # [1, 2, 3, 4, 5]
```

Il risultato è una lista, **non** cinque stampe. Una prima libreria `range` o `repeat` aggiungerebbe molto valore senza nuove keyword. Una sintassi `for` opzionale potrebbe in seguito essere tradotta in funzioni, ma andrebbe specificato se supporta effetti e early exit.

### `while` / `do-while`

**Stato: Componibile per computazioni pure; sintassi assente.** Basta la ricorsione con stato come parametro:

```nail
def until x limit =
  if x >= limit then x else until ( x + 1 ) limit ;
until 0 5 ; # 5
```

**Limite:** niente mutazione condivisa, niente garanzia qui documentata di eliminazione delle chiamate ricorsive di coda (TCO), niente `do` come sequenza imperativa.

### `for (final item in collection)`

**Stato: Componibile, con differenze.** Per trasformare usa `map`; per selezionare `filter`; per accumulare `fold`:

```nail
map ( fun n -> n * 2 ) [ 1 , 2 , 3 ] ;
fold ( fun sum n -> sum + n ) 0 [ 1 , 2 , 3 ] ;
```

Sono funzioni già presenti in `stdlib.nail`. Le liste Nail non sono automaticamente le `Iterable` lazy di Dart; gli effetti di un `for-in` non vengono emulati dalla sola `map`.

### `break`, `continue`, `return` anticipato

**Stato: Alternativa diversa / parziale.** Filtrare o interrompere una ricorsione con un ramo di `if` o `match` risolve numerosi algoritmi, ma non offre un controllo non locale su un ciclo imperativo. Se serviranno forme precise di early exit, valutare `takeWhile`, `find`, `foldUntil` prima di aggiungere keyword.

### `switch`, guardie e pattern Dart

**Stato: Parziale.** `match ... with` e `function | ...` su **liste** e **ADT** esistono già (con controllo di esaustività), ma non l'intera grammatica di Dart: switch-expression generalizzata, guardie su pattern, destrutturazione di record/mappe e pattern combinatori. Un `if` o un match esistente può risolvere il caso semplice.

## 2. Variabili, stato ed effetti

| Feature Dart | Stato Nail 0.49 | Alternativa / differenza |
| --- | --- | --- |
| `var` mutabile, `x++`, `x += 1` | **Assente** | `def` / `let` immutabili, ricorsione con accumulatori |
| `final` | **Simile, non identico** | binding Nail immutabile |
| `const` compile-time con semantica Dart | **Assente** | valori definiti con `def`, senza sistema di constant expressions Dart |
| `late` e inizializzazione differita | **Assente** | passare funzioni e dati esplicitamente |
| `print`, `stdout`, `stdin` | **Host** | la VM restituisce valori; I/O richiede API/permessi host o CLI |
| assegnazione a proprietà `obj.x = y` | **Assente** | creare un nuovo record; non è un setter |
| `assert(condition)` come statement | **Assente** | checker statico dove possibile; risultato esplicito per verifiche runtime |

**Valutazione:** meglio aggiungere una piccola libreria di iterazione e un canale di debug/console esplicito rispetto a introdurre subito variabili mutabili nell'intero linguaggio.

## 3. Tipi, collezioni e null safety

### `null`, `?`, `?.`, `??`, `!` e type promotion

**Stato: Assente nella sintassi e nel modello null di Dart; alternativa diversa già disponibile.** Nail ha somme algebriche generiche:

```nail
type Option a = None | Some a ;
def getOr fallback = function
  | None -> fallback
  | Some value -> value ;
getOr 0 ( Some 3 ) ;
```

L'ADT rende esplicita l'assenza, ma non equivale alle regole di null-safety e promozione di Dart. Una sintassi di convenienza futura dovrebbe abbassarsi su `Option`, se desiderata.

### Liste, `Map`, `Set`, indicizzazione

**Stato: Parziale.** Liste e algoritmi ricorsivi sono disponibili. `stdlib.nail` contiene già `mapEmpty`, `mapPut`, `mapFind`, `setEmpty`, `setAdd`, `setContains`: sono implementazioni **persistenti basate su liste**, non le collezioni hash mutable `Map<K,V>` e `Set<T>` di Dart. La sintassi di accesso `items[index]`, lo slicing e i collection `for` / `if` di Dart non sono sostituiti da queste API.

**Possibile priorità:** ergonomia dei metodi su collezioni, `range`, `take`, `drop`, `find`, `foldUntil`; prima valutare i costi di performance e la coerenza della stdlib.

### Generics e vincoli

**Stato: Parziale.** Tipi nominali parametrici (`type Box a { value a }`), funzioni HM e record strutturali esistono. La v0.49 offre inoltre **relazioni finite n-arie** dichiarate con righe `R : T1 ... Tn Result ;` e funzioni `def f x ... : R = ... ;`. Non ci sono tuttavia bounds generici nel senso Dart, typeclass aperte, impliciti o vincoli higher-order. Le funzioni con `: R` devono essere chiamate direttamente e completamente applicate.

### Pattern di record, destructuring e spread

**Stato: Parziale.** Costruzione e accesso di record nominali/anonimi ci sono; i destructuring pattern dei record Dart non sono un sostituto implementato. È possibile passare il record a una funzione e leggere i campi, senza matching strutturale generalizzato.

## 4. Funzioni e sintassi

| Feature Dart | Stato Nail | Nota |
| --- | --- | --- |
| funzioni top-level / anonime | **Disponibile** | `def`, `fun x -> ...` |
| funzioni di ordine superiore | **Disponibile con limiti** | `map`, `fold`; esclusi i valori di funzione sovraccaricata `: R` |
| chiamate con named arguments `f(x: 1)` | **Sintassi assente; alternativa parziale** | un record anonimo può raggruppare opzioni |
| parametri opzionali / default | **Assente come sintassi** | wrapper o record espliciti |
| `typedef` / alias di tipi Dart | **Non equivalente** | esistono tipi nominali e ADT; non inferire un sistema generale di alias |
| operator overloading definito dall'utente | **Assente** | righe di relazioni finite non definiscono nuove implementazioni runtime |
| `extension` / `extension type` | **Assente** | funzioni libere e wrapper nominali |
| documentazione `///` integrata con dartdoc | **Assente** | commenti `#`; tooling doc dedicato ancora da progettare |

## 5. Classi e modello a oggetti

Dart include `class`, proprietà mutabili, getter/setter, costruttori (anche `factory` e named), `static`, `extends`, `implements`, `abstract`, `sealed`, `mixin`, `with`, overriding e dispatch dinamico.

**Stato Nail: Assente come modello OO equivalente.** Il linguaggio dispone invece di:
- record nominali, generici e anonimi;
- ADT con costruttori e match esaustivo;
- funzioni di ordine superiore, composizione, funzioni associate *per convenzione* ai dati.

Questi strumenti coprono molti *problemi*, ma non replicano sottotipizzazione di classi, metodi con ricevitore implicito, ereditarietà, mixin o polimorfismo dinamico. **Non considerare la mancanza di OO automaticamente un bug.** Nail punta alla composizione di primitive e alla semplicità.

## 6. Moduli, pacchetti e tooling

| Feature Dart | Stato Nail 0.49 | Confine reale |
| --- | --- | --- |
| `import 'x.dart'` / `export` | **Parziale** | import/export di macro sorgente; interfacce dei moduli runtime via `ModuleLinker` e host |
| `show`, `hide`, `as`, `deferred` | **Assente** | non esiste un modulo sorgente Dart-equivalente |
| `pub`, package resolver / version solving | **Assente** | build e distribuzione si appoggiano al progetto/host |
| analizzatore e completamento IDE / Language Server | **Da sviluppare** | parser, checker e posizioni sorgente forniscono una base; nessun LSP completo dichiarato |
| compilazione diretta Nail → JS/PHP | **Assente** | oggi si compila in bytecode Nail eseguito da VM scritta in Haxe e distribuita su target JS/PHP |
| CLI/script/browser | **Disponibile tramite runtime** | consulta `RUNNING.md` |

**Nota:** l'intestazione `nail 0.49 ;` indica una revisione del linguaggio, non una garanzia di compatibilità pre-1.0. I test e la storia dei tag sono il riferimento per versioni vecchie.

## 7. Concorrenza, errori e I/O

### `async`, `await`, `Future`, `Stream`, `async*`, `await for`

**Stato: Assente come linguaggio.** Callback e risorse asincrone dell'host non diventano automaticamente `Future` Nail; non esiste una semantica di sospensione/ripresa documentata nel bytecode corrente. Evitare snippet che chiamano `await` o `yield` in Nail: non compilano. Decidere prima scheduler, capability e serializzazione dei moduli.

### `throw`, `try`, `on`, `catch`, `finally`, `rethrow`

**Stato: Assente come controllo di flusso linguistico.** Il pattern idiomatico è un risultato algebrico:

```nail
type Check a = Accepted a | Rejected Text ;
def check x = if x > 0 then Accepted x else Rejected " non positivo " ;
```

Le capability host per I/O usano analogamente `CoreOk` e `CoreErr`, con grant separati. Non equivalgono a catturare arbitrariamente gli errori della VM.

### File, rete, clock, processi, FFI

**Stato: Parziale / host.** Esistono primitive/capability controllate per risorse come lettura e scrittura di testo, con permessi. Non sono la libreria `dart:io`, `dart:async` o `dart:ffi`. Non scrivere documentazione che faccia sembrare aperto l'accesso al filesystem per default.

## 8. Macro e metaprogrammazione: attenzione ai falsi «manca»

**Disponibile oggi:** template macro `macro / quote / unquote / expand` statiche e igieniche, importabili con vincoli di dialetto/versione; `Syntax` e il sistema procedurale esistono e sono già impiegati nell'implementazione per generare/abbassare record e ADT.

**Non dedurne automaticamente:** un linguaggio pubblico completo per plugin di compilatore, reflection runtime generale, transformer arbitrari richiamabili da qualsiasi sorgente o un sistema di typeclass aperte. Per la differenza tra template macro e generazione procedurale, rimandare a `MACRO-AUDIT.md` e ai test di `ProceduralTransformerTestMain`.

## 9. Matrice delle priorità da discutere

| Idea | Valore pratico | Costo/rischio | Suggerimento |
| --- | --- | --- | --- |
| `range`, `repeat`, `take`, `find`, `foldUntil` in stdlib | **Alto** | basso-medio | sperimentare *senza* nuova sintassi |
| esempi esercitabili e golden tests per cookbook | **Alto** | basso | migliorano anche regressioni/CI |
| debug/console capability con output esplicito | **Alto** | medio (permessi/portabilità) | separare valori ed effetti |
| pattern matching più ergonomico (record, guardie) | medio-alto | medio | sfruttare Syntax/lowering prima di estendere il core |
| applicazione higher-order di funzioni `: Relation` | medio-alto | alto (soundness, ABI) | studio mirato, non zucchero sintattico |
| parametri opzionali e named | medio | medio | provare record anonimi per prima cosa |
| TCO o iterazione efficiente e garantita | medio-alto | medio-alto | misurare profondità reale dei casi |
| `async/await` e stream | dipende dai casi d'uso | **alto** | solo dopo una semantica host/VM definita |
| `var`, `for`, `while` imperativi | medio | medio-alto | non introdurli solo per somigliare a Dart |
| gerarchia classi, mixin, eccezioni unchecked | incerto per Nail | **alto** | nessun impegno; valutare alternative funzionali |

## 10. Come mantenere il lookbook onesto

1. Quando si aggiunge una feature, spostare nel [cookbook comparativo](./COOKBOOK-DART.md) almeno un caso eseguibile e aggiornare il suo stato qui.
2. Per ogni promessa di equivalenza, distinguere **valore**, **side effect**, **prestazioni**, **tipi** e **portabilità Haxe/JS/PHP**.
3. Un esempio che non passa il parser/checker nella versione indicata deve essere etichettato *proposta di sintassi*, mai codice pronto.
4. Mantenere le versioni storiche nei tag: prima della 1.0 non c'è retrocompatibilità garantita.
