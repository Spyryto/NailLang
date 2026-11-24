# Nail × Dart — cookbook comparativo (Nail 0.49)

[Cookbook generale](./COOKBOOK.md) · [Language Tour Nail](./LANGUAGE-TOUR.md) · [Lookbook delle lacune](./LOOKBOOK.md) · [Esecuzione](./RUNNING.md)

Per il confronto funzionale complementare: [Nail × F#](./COOKBOOK-FSHARP.md).

**Riferimento:** [Dart — Introduction to Dart](https://dart.dev/language), incluse le sue sezioni *Hello World, Variables, Control flow, Functions, Comments, Imports, Classes, Enums, Inheritance, Mixins, Interfaces, Async, Exceptions*. Gli esempi qui sono originali, non una trascrizione di quelli di Dart.

**Regole di lettura.** Il codice Nail di questa pagina usa `nail 0.49 ;` (ripetilo in testa a ogni file) e separa con spazi i token e la punteggiatura. Le definizioni terminano con `;`. Ogni espressione finale restituisce **un valore alla VM**: questo non equivale a stampare sulla console né a produrre effetti collaterali. Per `map`, `filter`, `fold` e `length` serve la libreria standard caricata dalla CLI/host. Lo stato delle equivalenze è descritto in [LOOKBOOK.md](./LOOKBOOK.md).

## Percorso rapido

| Dart | Nail 0.49 | Che cosa cambia |
| --- | --- | --- |
| `print(...)` | espressione finale, per esempio `42 ;` | il valore torna all'host; stdout non è automatico |
| `var`, `final` | `def` e `let ... in` | binding immutabili; niente assegnazioni |
| `if/else` | `if ... then ... else ...` | è un'espressione con un risultato |
| `for` / `while` | ricorsione; `map` / `fold` | ripetizione sì, statement di ciclo no |
| funzioni / closure | `def`, `fun`, applicazione parziale | funzioni currificate |
| `List` / `Iterable` | liste, `map`, `filter`, `fold` | collezioni persistenti; niente `for-in` |
| record | record nominali e anonimi | campi letti con `value . field` |
| `enum` / `switch` | ADT e `match` / `function` | pattern matching su costruttori |
| `List<T>` / generics | `type Box a { value a }` | polimorfismo HM, non classi Dart |
| `import` | import di macro; moduli compilati via host | non è il loader di Dart |
| classi / inheritance / mixins | composizione di record e funzioni | non esiste un equivalente OO generale |
| `async`, `await`, `Future` | — | non ancora una feature del linguaggio |
| `throw`, `try` / `catch` | ADT `Ok/Err` o `CoreResult` | errori come valori, non eccezioni |
| null safety | tipo somma `Option a` | niente `null`, `?.`, `??` |

## 1. Hello World — valore contro effetto

Dart:

```dart
void main() {
  print('Ciao!');
}
```

Nail:

```nail
nail 0.49 ;
" Ciao! " ;
```

Il programma Nail restituisce un `Text`. La CLI può mostrarlo come risultato; **non esiste qui una chiamata Nail a stdout**. Per stampare realmente servirebbe un'operazione concessa dall'host. Gli spazi **all'interno** delle virgolette fanno parte del testo: Nail usa token separati da spazi.

## 2. Variabili, costanti e ambito

Dart:

```dart
final birth = 1977;
final age = 2026 - birth;
```

Nail:

```nail
nail 0.49 ;
def birth = 1977 ;
def age = 2026 - birth ;
age ;
```

Per una variabile locale:

```nail
let x = 6 in x * 7 ;
```

`def` e `let` creano binding, non caselle mutabili: la riassegnazione `x = x + 1` in stile Dart **non** è disponibile.

## 3. Numeri, inferenza, conversioni esplicite

Dart:

```dart
final seconds = 60 / 97; // double
```

Nail:

```nail
nail 0.49 ;
def seconds = 60 / 97 ;  # Ratio esatto
seconds ;
toFloat seconds ;        # Float soltanto su richiesta
```

In Nail 0.49 `Int`, `Ratio`, `Float` sono domini distinti; `1 + 2.0` non converte automaticamente. Il letterale `2.0` è `Float`, `2` è `Int`.

## 4. If ed espressioni condizionali

Dart:

```dart
String kind(int year) => year >= 2001 ? 'recent' : 'old';
```

Nail:

```nail
nail 0.49 ;
def kind year = if year >= 2001 then " recente " else " passato " ;
kind 2026 ;
```

Entrambi i rami producono un valore dello stesso tipo. Un `if` senza `else` non ha qui il significato dello statement Dart.

## 5. Come scrivere un semplice ciclo (for)

Dart, con side effect:

```dart
for (var i = 1; i <= 5; i++) {
  print(i);
}
```

Nail, **equivalente per i valori calcolati**, non per la stampa:

```nail
nail 0.49 ;
def range start stop =
  if start > stop then []
  else cons start ( range ( start + 1 ) stop ) ;

range 1 5 ;  # [1, 2, 3, 4, 5]
```

La ricorsione fornisce condizione di uscita, avanzamento e risultato. `range` qui **è una funzione definita dall'utente**, non una primitiva della standard library. Per una sequenza discendente:

```nail
def countdown n =
  if n <= 0 then []
  else cons n ( countdown ( n - 1 ) ) ;
countdown 3 ;  # [3, 2, 1]
```

### Variante tipo while, senza costruire una lista

Dart:

```dart
var x = 0;
while (x < 5) x++;
```

Nail:

```nail
def until value limit =
  if value >= limit then value
  else until ( value + 1 ) limit ;

until 0 5 ;  # 5
```

**Attenzione:** la semantica non è imperativa: ogni invocazione ha argomenti propri. Non assumere che il compilatore garantisca la tail-call optimization per cicli molto lunghi. Nail non ha qui `break`, `continue`, `for`, `while` come parole chiave.

## 6. Iterare e accumulare: preferisci map, filter, fold

Dart:

```dart
final doubled = [1, 2, 3].map((x) => x * 2).toList();
final selected = [1, 2, 3, 4].where((x) => x > 2).toList();
final sum = [1, 2, 3, 4].fold(0, (a, b) => a + b);
```

Nail:

```nail
nail 0.49 ;
def twice x = x * 2 ;
map twice [ 1 , 2 , 3 ] ;                       # [2, 4, 6]
filter ( fun x -> x > 2 ) [ 1 , 2 , 3 , 4 ] ;  # [3, 4]
fold ( fun total x -> total + x ) 0 [ 1 , 2 , 3 , 4 ] ; # 10
```

Queste tre funzioni sono **già implementate in `stdlib.nail` usando ricorsione e pattern matching**, non scorciatoie Haxe. La loro valutazione è quella di liste Nail, non la lazy `Iterable` di Dart.

## 7. Funzioni, lambda, higher-order

Dart:

```dart
int twice(int x) => x * 2;
final result = [2, 4].map(twice).toList();
```

Nail:

```nail
nail 0.49 ;
def twice x = x * 2 ;
def apply f x = f x ;
apply twice 21 ;
map ( fun x -> x * 3 ) [ 2 , 4 ] ;
```

Un'applicazione parziale ordinaria:

```nail
def append prefix suffix = textConcat prefix suffix ;
def hello = append " Ciao " ;
hello " Nail " ;
```

**Eccezione importante:** le funzioni annotate con relazioni finite (`: Add`, `: Div`, ecc.) richiedono una chiamata diretta e completamente applicata; non sono ancora passabili liberamente come valori higher-order.

## 8. Record nominali, anonimi e generici

Dart:

```dart
final song = (title: 'Swing', bpm: 120);
final tempo = song.bpm;
```

Nail, record strutturale anonimo:

```nail
nail 0.49 ;
def song = { title = " Swing " , bpm = 120 } ;
song . bpm ;
```

Nail, record nominale tipizzato:

```nail
type Song { title Text bpm Int } ;
def item = Song { bpm = 120 , title = " Swing " } ;
item . title ;
```

Nail, tipo generico:

```nail
type Box a { value a } ;
def boxed = Box { value = 42 } ;
boxed . value ;
```

I record permettono di rappresentare dati e opzioni simili ai named arguments, **ma non implementano costruttori, metodi o ereditarietà Dart**.

## 9. Enum, sealed-like unions e pattern matching

Dart:

```dart
enum Status { draft, published }
final published = status == Status.published;
```

Nail:

```nail
nail 0.49 ;
type Status = Draft | Published ;
def isPublished = function
  | Draft -> false
  | Published -> true ;
isPublished Published ;
```

Con valori associati:

```nail
type Event = Rest | Played Int ;
def bpm = function
  | Rest -> 0
  | Played value -> value ;
bpm ( Played 116 ) ;
```

Nail verifica l'esaustività dei match sui costruttori di un tipo somma. Non equivale però all'intero sistema di pattern Dart (`switch` su qualunque struttura, guardie, destructuring su mappe/record, ecc.).

## 10. Liste e pattern matching

Dart:

```dart
int count(List<int> items) => items.length;
```

Nail (implementazione didattica, equivalente a `length`):

```nail
nail 0.49 ;
def count xs = match xs with
  | [] -> 0
  | _ :: rest -> 1 + count rest ;

count [ 10 , 20 , 30 ] ;
```

Questa forma rende esplicito *come* si attraversa una lista. `head`, `tail`, `cons`, `length` e le funzioni di ordine superiore coprono molti casi senza introdurre indicizzazione mutabile.

## 11. Option invece di null

Dart:

```dart
int? amount;
final result = amount ?? 0;
```

Nail:

```nail
nail 0.49 ;
type Option a = None | Some a ;
def orElse fallback option = match option with
  | None -> fallback
  | Some value -> value ;

orElse 0 None ;        # 0
orElse 0 ( Some 7 ) ;  # 7
```

È un modello esplicito a valori; non include la sintassi Dart `?`, `?.`, `??`, `!`, né la type promotion.

## 12. Errori recuperabili invece di throw/try

Dart:

```dart
int positive(int x) {
  if (x <= 0) throw ArgumentError('positive only');
  return x;
}
```

Nail, risultato esplicito:

```nail
nail 0.49 ;
type Check a = Accepted a | Rejected Text ;
def positive x =
  if x > 0 then Accepted x else Rejected " non positivo " ;

def readResult = function
  | Accepted x -> x
  | Rejected reason -> 0 ;

readResult ( positive 3 ) ;
```

Questa ricetta non introduce eccezioni. Per errori di I/O esistono `CoreOk` / `CoreErr` nelle capability host: consulta [COOKBOOK.md](./COOKBOOK.md) e [HOST-CAPABILITIES.md](./HOST-CAPABILITIES.md).

## 13. Import e organizzazione dei moduli

Dart:

```dart
import 'library.dart';
```

Nail ha **due meccanismi da non confondere**: import di *macro sorgente*, e collegamento di *moduli runtime compilati* attraverso interfacce e manifesti dell'host. Esempio verificabile di import di macro:

```nail
# examples/macros/numbers.nail
nail 0.49 ;
macro next x = quote ( unquote x + 1 ) ;
export next ;
```

```nail
# examples/macro-next-049.nail
nail 0.49 ;
import next from numbers ;
expand next 41 ;
```

Per eseguire questo caso sulla distribuzione boot PHP:

```sh
php build/boot/php/index.php --macro-dir examples/macros examples/macro-next-049.nail
```

L'import di macro richiede un dialetto numerico/versione coerente. **Non** è un generico import di moduli Dart con namespace, package manager e inizializzazione automatica.

## 14. Classi, interfacce, ereditarietà e mixin: composizione, non equivalenza

Dart ha metodi, stato di istanza, costruttori multipli, sottotipizzazione, `extends`, `implements` e `with`. Nail può modellare *i dati* con record e *il comportamento* con funzioni:

```nail
nail 0.49 ;
type Spacecraft { name Text launched Bool } ;
def describe craft =
  if craft . launched then " lanciata " else " non lanciata " ;

def voyager = Spacecraft { name = " Voyager " , launched = true } ;
describe voyager ;
```

Questo **non** replica gerarchie OO, overriding, dispatch dinamico né interfacce Dart. Per una decisione progettuale è più utile chiedersi se la composizione copra il caso d'uso che inseguire la stessa sintassi.

## 15. Async, streams, exceptions, assert e altri confini

Non sono ancora esempi Nail eseguibili equivalenti di:

- `Future`, `async`, `await`, `async*`, `Stream`, `await for`;
- `throw`, `try`, `on`, `catch`, `finally`, `rethrow`;
- `assert` come costrutto; `for`, `while`, `do`, `break`, `continue`;
- `class`, `extends`, `mixin`, `interface`, `factory`, `extension`.

Il [Lookbook](./LOOKBOOK.md) spiega il livello preciso della lacuna, i workaround reali, l'utilità e i possibili trade-off.

## 16. Bonus: Nail ha macro statiche che non sono un calco di Dart

```nail
nail 0.49 ;
macro next x = quote ( unquote x + 1 ) ;
expand next 41 ;  # Int 42
```

Le template macro Nail sono espanse in compilazione. Separatamente, il sistema `Syntax` e i generatori procedurali sono usati anche internamente per abbassare dichiarazioni strutturate in forme Nail più semplici. Non attribuire a questa singola macro capacità di reflection o generazione arbitraria accessibile al programma sorgente.

## Prova pratica

Il file [`examples/dart-tour-049.nail`](./examples/dart-tour-049.nail) riunisce esempi concreti della pagina; le ricette indipendenti qui sopra possono essere copiate in file separati. Dopo aver creato il runtime:

```sh
haxe seed-image.hxml
haxe boot-php.hxml
php build/boot/php/index.php examples/dart-tour-049.nail
```

Oppure segui la guida [RUNNING.md](./RUNNING.md) per Node o per il browser. **Verifica dell'eseguibilità:** questi esempi sono basati sulla grammatica e sui test del repository; la loro introduzione nella documentazione non costituisce da sola un nuovo test CI eseguito.

**Principio:** Cookbook = *come svolgere un lavoro oggi*. [Lookbook](./LOOKBOOK.md) = *cosa non si può esprimere ancora, cosa si può comporre e cosa forse non serve introdurre*.
