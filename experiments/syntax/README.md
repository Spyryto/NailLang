# Historical experiment notes

The following notes document the branch before promotion to the canonical 0.62 candidate. The patch is retained in Git history at commit `127e73eafcb1de8162fa2b04939616a765585d45`; it is no longer a build input. Current changes and limitations are in [0.62 candidate notes](../../docs/releases/0.62.md).

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

Il parser Nail nella stdlib rifattorizzata riconosce identificatori con
trattino e pipeline (verificati sui tre target). Le label sono ora
implementate in una seconda iterazione ancora in validazione. Per
rendere visibili le label della libreria caricata prima del sorgente
utente, il parser Haxe ora accetta uno snapshot di metadati e VM e
checker lo aggiornano secondo la semantica della rispettiva operazione:
la VM pubblica le label dopo ogni definizione riuscita, mentre il
checker le pubblica soltanto dopo il successo dell'intera unità.

```haxe
var vm = new nail.Vm(70000000);
vm.runExperimental(refactoredStdlib);
var result = vm.runPlainExperimental('map using: ( fun x -> x + 1 ) items: [ 1 , 2 ] ;');
```

Il checker può verificare separatamente la sezione collezioni e poi
il chiamante. Non è ancora una ABI pubblica: non si assegnano alla
libreria legacy tipi numerici moderni e non si finge che tutta la
stdlib (che contiene riferimenti in avanti) sia già verificata con HM.

## Primo allineamento del parser Nail

La stessa patch sperimentale estende `isIdentTail`, `infixPower` e
`parseSuffix` (nessun nuovo costruttore o opcode). `>>` ha precedenza
25, è associativo a sinistra e genera `syntaxApply rhs lhs`.
I trattini separano segmenti non vuoti di un identificatore. Il parser
ufficiale continua a rifiutare entrambe le forme. Il test
`SelfSyntaxExperimentTestMain` confronta esecuzione e bytecode con il
parser Haxe, e include input malformati. Questa prima estensione è
stata validata sui tre target. La sintassi discorsiva è sospesa.


## Secondo allineamento: argomenti nominati

Il parser Nail nella variante patchata conserva temporaneamente
`ExpDefinition` (label pubbliche + definizione) e `ExpCall`
(applicazione di superficie). `expFormsScoped` registra i parametri
pubblici prima di risolvere il corpo. `expLower` attraversa
Lambda/Apply/If rispettando i binder lessicali; `expAssign` assegna
gli argomenti agli slot in ordine di sorgente. I marker spariscono
prima della macro expansion e della compilazione: nessuna modifica
al Core AST, a SyntaxBridge o al bytecode.

Le chiamate sature ordinate usano direttamente Apply, come il parser
Haxe. Negli altri casi vengono emesse catture e lambda per i parametri
mancanti. I nomi privati delle catture sono deterministici e locali
alla chiamata; non devono necessariamente coincidere con il contatore
del parser Haxe. I test confrontano il bytecode delle chiamate ordinate
e i risultati di quelle riordinate/parziali. Sono inclusi casi
negativi di label sconosciute, duplicate e oscurate da binder.

Confini: label disponibili nello stesso sorgente, non ancora tra
sessioni del parser Nail; chiamate nominate in contesti aperti
rifiutate esplicitamente; nessuna label esplicita nelle dichiarazioni
macro. L'allineamento dei predicati numerici è descritto nella sezione
successiva. La variante ufficiale non cambia.


## Checker Nail: inferenza numerica vincolata

La patch conserva le obbligazioni numeriche nella lista persistente
delle sostituzioni, accanto ai guard di riga e ai vincoli Eq.
`tcInferNumericApply` introduce una variabile per il risultato e
un predicato quando gli operandi non sono ancora risolti.
Il risolutore prova le righe di `tcDefaultRelation` usando
l'unificazione esistente; una riga unica determina le sostituzioni.
L'ultima iterazione propaga anche i tipi comuni a tutte le righe
compatibili, ripetendo il passaggio fino al punto fisso.

`tcGeneralizeNumeric` seleziona i componenti di predicati raggiungibili
dal tipo da generalizzare, escludendo quelli connessi allo scope
esterno. Le obbligazioni non selezionate restano pendenti; quelle
generalizzate sono conservate in un quinto campo privato opzionale
`TCNumericQuant` dello schema, assente negli schemi ordinari.
`tcInstantiateNumeric` usa la stessa rinomina dei quantificatori.
Le valutazioni e le righe di relazioni esplicite rifiutano
obbligazioni ancora ambigue. La serializzazione pubblica rifiuta
gli schemi numerici qualificati anziché perdere informazioni.

```nail
nail 0.61 ;
def summ x y = x + y ;
summ 2 3 ;
summ 1.5 2.5 ;
def half x = x / 2 ;
half 3 ;
```

Le specializzazioni indipendenti e la generalizzazione locale sono
validate su Haxe, JS e PHP (CI 45575052597: 267 verifiche per target).
La propagazione delle colonne comuni è validata sui tre target
(CI 45582160770: 286 verifiche per target): per esempio, il risultato di `half` è Ratio anche
prima di conoscere se x è Int o Ratio. L'obbligazione relativa
all'operando non viene eliminata.

La suite SelfSyntaxExperimentTestMain confronta il checker Nail con
quello Haxe, include casi negativi e controlla direttamente gli schemi
inferiti. Non implica equivalenza completa dei due checker: in
particolare la diagnostica e l'interazione con tutte le feature
richiedono una verifica dedicata. I confronti numerici ordinati
usano ora la stessa tabella interna dei tipi compatibili, con
risultato Bool; CI 45586136113 verde su Haxe e JS, suite parser PHP
verde ma confronto finale PHP annullato da un commit successivo. L'ABI, la stdlib ufficiale e main restano invariati.


## Consolidamento delle label tra unità

Le definizioni runtime sono immutabili e non transazionali a livello
di programma: se una forma fallisce, le definizioni precedenti
rimangono disponibili. La VM deve quindi pubblicare le label
insieme alla singola definizione riuscita, non alla fine di run.
Nessuna label è pubblicata per un corpo fallito o una forma non
eseguita. Il checker mantiene il comportamento transazionale già
esistente; la fusione dei metadati non elimina quelli delle unità
precedenti quando viene fornito un parser indipendente.

Una dichiarazione duplicata non può sovrascrivere le label:
entrambi i parser sperimentali la rifiutano. Le definizioni
caricate con sintassi ordinaria non acquisiscono automaticamente
label. Il parser Nail mantiene ancora solo metadati dello stesso
sorgente; il supporto tra unità è della VM/checker con parser Haxe.
I nuovi casi negativi e di recupero sono stati validati sui tre target.

Prima di qualsiasi promozione: chiarire la politica sui metadati
tra unità per il parser Nail e decidere come integrare la variante
patchata. Nessun merge automatico in main.


## Bootstrap sperimentale riproducibile — risultato verificato

Commit di riferimento: `3e9a2a37af9d100bfd4357578d92d57278698a45`.

- [CI sperimentale](https://github.com/Spyryto/NailLang/actions/runs/45598491439): 978 verifiche (326 per target) e bootstrap completo verdi.
- [CI ordinaria](https://github.com/Spyryto/NailLang/actions/runs/45598500543): nove job verdi.
- Stage zero Haxe, stage uno Nail e stage due Nail producono lo stesso
  nastro di bytecode ordinato, senza normalizzazione aggiuntiva.
- SHA-256 del nastro: `f4741db092193d23d80649e76acae74220d8b5f7562655bd23c672b6310a948b`.
- Le distribuzioni source-free JS e PHP eseguono il programma di prova;
  il controllo dei confini esclude il parser e il compilatore Haxe.
  Il test JS verifica anche la compilazione statica Nail e il rifiuto
  di una chiamata numerica invalida.
- Tempo misurato del fixed point nel job CI: circa 73 minuti
  (da 10:49:13 a 12:02:21 UTC, inclusa la compilazione del driver).
  È un costo concreto di consolidamento, non un benchmark del
  linguaggio. Il candidato è corretto nei casi verificati, ma non
  abbiamo ancora profilato il costo delle nuove traversate del parser.

### Decisione di integrazione proposta (non ancora applicata)

Non mantenere una patch permanente come seconda stdlib. Nella prossima
versione, integrare le modifiche nel sorgente canonico e costruire il
bootstrap da quello, rendendo coerente il gate della sintassi Haxe
con la versione ufficiale. Conservare gli artefatti storici, non
promettere retrocompatibilità pre-1.0. Prima di farlo, decidere se
le label sono soltanto metadati di unità di compilazione o una
proprietà esportabile delle definizioni. L'ABI dei moduli rimane
invariato in questo esperimento. Nessuna estensione ai contesti DSL
aperti o sintassi discorsiva. La PR #63 resta Draft.
