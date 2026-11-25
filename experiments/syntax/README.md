# Esperimento di sintassi: identificatori, argomenti nominati, applicazione

**Ramo:** `experiments/syntax-curried-keywords`. Nessuna modifica alla versione
ufficiale Nail 0.61. Non distribuire questo parser come runtime stabile.

## Sintassi disponibile solo in modalità sperimentale

```nail
nail 0.61 ;

def pair first second = first * 10 + second ;

pair 4 2 ;
pair second: 2 first: 4 ;
pair 4 second: 2 ;
pair first: 4 2 ;

def plus-two = pair second: 2 ;
plus-two 4 ;

def add-one n = n + 1 ;
41 >> add-one ;
```

Le due forme posizionali e nominate sono **la stessa funzione curried**.
La trasformazione del parser usa solamente `Var`, `Lambda` e `Apply`,
senza nuovi nodi, opcode, VM o FFI.

Una chiamata con argomenti nominati riconosce i parametri della funzione
già dichiarata nello stesso file o in un sorgente precedentemente caricato
nella stessa sessione sperimentale. Gli argomenti forniti vengono catturati
una volta nell'ordine in cui sono scritti. I parametri non forniti
rimangono lambda curried nell'ordine originale di dichiarazione.
Una chiamata satura i cui argomenti sono forniti nell'ordine originale
viene invece ridotta alle normali applicazioni, senza lambda di cattura.

`value >> fn` si riduce a `fn value`. È associativo a sinistra e ha
precedenza inferiore a operatori aritmetici e confronti. Un nome con
trattino come `add-one` è un identificatore intero; la sottrazione
mantiene `a - b` con spazi intorno.

## Label pubbliche e nomi locali distinti

```nail
def fraction numerator: a denominator: b = a / b ;
def half = fraction denominator: 2 ;
half 3 ; # 3/2
```

`numerator:` e `denominator:` sono le label pubbliche, mentre
`a` e `b` sono i binder lessicali nel corpo della funzione.
Il parser conserva le label come metadati locali alla sorgente;
l'AST contiene soltanto i binder e le applicazioni ordinarie.

Una dichiarazione semplice (`def fraction a b = a / b ;`) usa
i nomi locali anche come label. Le due forme possono essere miste
nella stessa dichiarazione. Le chiamate posizionali continuano
a funzionare. Label e binder hanno namespace distinti: una label
duplicata o un binder duplicato viene rifiutato, ma i nomi possono
incrociarsi tra i due namespace. Un binder rinominato non è una
seconda label pubblica. Nessuna modifica al currying.

## Modalità esplicita

Nel codice Haxe che ospita Nail:

```haxe
var vm = new nail.Vm();
var result = vm.runPlainExperimental(source);
```

Il normale `vm.runPlain(source)` e `new Parser(source)` **non attivano**
questa sintassi. Il parser rimane quello Haxe e il bootstrap scritto in
Nail non conosce ancora le nuove forme.

### Controllo statico esplicito

```haxe
var checker = new nail.TypeChecker();
var types = checker.checkExperimental(source);
```

Si usa lo stesso parser sperimentale e l'inferencer HM della 0.61,
esteso in questo ramo con predicati numerici inferiti. Per esempio
`def summ x y = x + y ;` ha firma `Add a b c => a -> b -> c`.
Le annotazioni sono facoltative quando i vincoli possono essere risolti.

```nail
def fraction numerator: ( a : Int ) denominator: ( b : Int ) = a / b ;
def half = fraction denominator: 2 ;
half 3 ; # Ratio
```

La versione annotata ha firma `Int -> Ratio`. Anche la versione non
annotata è ammessa dal checker sperimentale, conservando il predicato
numerico durante il currying. Un risultato numerico ancora ambiguo
viene rifiutato. L'ABI dei moduli non esporta questi predicati. Una variabile lessicale omonima (parametro, let, pattern)
oscura le label della definizione globale: la chiamata posizionale
resta ammessa, quella nominata viene rifiutata. Le label non sono
ancora proprietà delle funzioni come valori di prima classe.

## Confini, da verificare prima di ogni promozione

- Identificatori composti stile `def set contains: item in: entries`
  **non** sono ancora supportati. Mancano le regole di risoluzione dei nomi.
- VM e checker conservano le label dei sorgenti caricati esplicitamente
  in modalità sperimentale. `loadStdlib()` ordinario, import, extern
  e il browser Lab non predispongono ancora la variante della libreria.
- Le keyword richiedono il `:`: `item: 2`, non `item 2`.
- La punteggiatura richiede ancora spazi intorno ai token.
- Il checker Haxe, `Main.analyzeExperimental` e Nail Lab (modalità
  sperimentale separata) usano questo percorso; SourceAnalysis standard
  e il bootstrap ufficiale no.
- Le funzioni con contratti numerici relazionali conservano i limiti
  esistenti sulle applicazioni parziali.
- Il riscritto usa nomi interni impossibili da scrivere nel sorgente
  (`#exp_...`), così non può catturare accidentalmente variabili locali.

## Verifica

```sh
haxe syntax-experiment-test-interp.hxml
haxe syntax-experiment-test-js.hxml && node build/tests/syntax-experiment.js
haxe syntax-experiment-test-php.hxml && php build/tests/php-syntax-experiment/index.php
```

La CI dedicata a questo ramo esegue tutti e tre i target, compresi
i casi negativi e la compatibilità del parser standard. Prima di
adottare qualsiasi sintassi, dobbiamo discutere e verificare i
conflitti con nomi omonimi, parametri con default e API host.


## Dogfooding: refactoring della vera stdlib

`stdlib-refactor.patch` è una variante incrementale dell'intera
`stdlib.nail` (529 definizioni originali). Non cambia il file ufficiale
né introduce una seconda copia versionata di oltre 5.600 righe.

```sh
mkdir -p build/tests
patch --batch --fuzz=0 -o build/tests/stdlib-experimental.nail stdlib.nail experiments/syntax/stdlib-refactor.patch
haxe -cp src -main StdlibSyntaxExperimentTestMain -resource stdlib.nail@stdlib -resource build/tests/stdlib-experimental.nail@stdlib-experimental --interp
```

Il candidato rimane nella modalità numerica legacy della stdlib:
non inserire l'header 0.61, che ne cambierebbe i tipi e i risultati.
La CI confronta le due librerie complete nei runtime AST e bytecode,
le firme delle collezioni e il bytecode prodotto da programmi ordinari
attraverso il compilatore Nail. Non prova ancora l'equivalenza di tutte
le funzioni né l'auto-parsing della nuova sintassi.

Scelte di leggibilità, non regole obbligatorie:

- Pipeline per catene di trasformazioni e accessori annidati.
- Label pubbliche `using:`, `items:`, `initial:`, `predicate:` per
  map/filter/fold; sono proposte da valutare, non un'API definitiva.
- Chiamate nominate per rendere espliciti indici, limiti e accumulatori.
- Chiamate posizionali nei percorsi ricorsivi per concisione. Dopo
  il dogfooding, il lowering ordinato e saturo è identico a quello
  posizionale; riordinamento e currying non prefisso mantengono le catture.
- Un solo esperimento con il trattino (`tokenize-at`); si conserva
  `tokenizeAt` come alias durante il confronto.
- Non riscrivere i costruttori o i nomi di funzioni host.

Il parser Nail deve ancora imparare la superficie sperimentale. Per
rendere visibili le label della libreria caricata prima del sorgente
utente, il parser Haxe ora accetta uno snapshot di metadati e VM e
checker lo aggiornano dopo il successo della rispettiva operazione.

```haxe
var vm = new nail.Vm(70000000);
vm.runExperimental(refactoredStdlib);
var result = vm.runPlainExperimental('map using: ( fun x -> x + 1 ) items: [ 1 , 2 ] ;');
```

Il checker può verificare separatamente la sezione collezioni e poi
il chiamante. Non è ancora una ABI pubblica: non si assegnano alla
libreria legacy tipi numerici moderni e non si finge che tutta la
stdlib (che contiene riferimenti in avanti) sia già verificata con HM.
