# NailSeed v0.3 — Minimal Functional Core

Versione sperimentale: una semantica funzionale piccola, scritta e testata prima in JavaScript. Le versioni precedenti restano indipendenti. Il codice non è ancora self-hosted né compatibile a livello di bytecode con NailVM 0.1.

## Principio

**Variabili e funzioni con nome in superficie; nessuno stack visibile.** Il parser usa solo token separati da spazi e trasforma lo zucchero sintattico in cinque nodi espressivi:

1. `literal(value)` — numero finito, booleano o lista vuota.
2. `var(name)` — risoluzione di nome in ambiente lessicale.
3. `lambda(parameter, body)` — funzione di un solo argomento con closure.
4. `apply(function, argument)` — applicazione di funzione (valutazione eager).
5. `if(condition, then, else)` — solo un ramo viene valutato.

`def` è una forma di programma esterna alle espressioni: aggiunge un nome al dizionario globale; più argomenti diventano lambda annidate. `+`, `-`, `*`, `/`, i confronti e gli elenchi `[ ... ]` sono **desugaring** verso `apply` di primitive currificate. Il parser non produce nodi `binary`, `list`, `section` o `pipe`.

## Esempio

```nail
# Spazi intorno a ogni delimitatore e operatore.
def twice x = x * 2 ;
def square x = x * x ;
def add a b = a + b ;
def inc = add 1 ;

def factorial n =
  if n < 2 then 1
  else n * factorial ( n - 1 ) ;

map twice [ 1 , 2 , 3 ] ;  # dopo il caricamento di stdlib.nail
```

`[]` è uno speciale **singolo token** accettato come lista vuota, alternativo a `[ ]`. `#` introduce un commento fino a fine riga, se preceduto da spazio o inizio riga. Non esistono stringhe letterali in questa versione.

## Tokenizzazione e precedenza

- Tokenizzazione con divisione per whitespace: `source.match(/\S+/g)` dopo rimozione dei commenti.
- Sono richiesti spazi attorno a `(`, `)`, `[`, `]`, `,`, `;`, `=`, infissi e `->`.
- Precedenza: applicazione (70) > `* /` (50) > `+ -` (40) > confronti/uguaglianza (30).
- Applicazione e operatori infissi associativi a sinistra; parentesi per raggruppare.
- `fun x y -> e` e `def f x y = e ;` vengono desugared in `fun x -> fun y -> e`.
- `if` richiede un booleano reale, mai truthiness JS.
- `def f x = ... ;` ammette ricorsione tramite risoluzione delle definizioni globali.
- Il valore di un'espressione terminata da `;` viene restituito da `run()` in un array di risultati. Le definizioni non producono risultati.

### Esempio di desugaring

```text
def twice x = x * 2 ;
```

Il corpo di `twice` è sostanzialmente:

```text
lambda("x", apply(apply(var("*"), var("x")), literal(2)))
```

Per una lista, `[ a , b ]` diventa una catena di applicazioni a un `cons` interno non nominabile da sorgente, terminata da un valore vuoto. Questo evita che una variabile utente chiamata `cons` cambi il significato della sintassi delle liste.

## Primitive host: minime, esplicite

- Numeriche binarie (argomenti numerici finiti): `+`, `-`, `*`, `/`.
- Confronti numerici binari: `<`, `<=`, `>`, `>=`.
- Uguaglianza strutturale (numeri, booleani e liste annidate): `==`, `!=`.
- Liste: `nil` (lista vuota), `cons`, `head`, `tail`, `isEmpty`.

`head` e `tail` su lista vuota producono errore; anche divisione per zero, `if` con condizione non booleana, applicazione a non-funzione, nomi sconosciuti e definizioni duplicate producono errore. In v0.3 i numeri sono IEEE 754 double finiti; l'aritmetica che produce `Infinity` o `NaN` viene rifiutata. Non c'è ancora un type checker statico.

Le liste sono array JavaScript congelati (copia ad ogni `cons` e `tail`), non una struttura persistent-linked ottimizzata. **Limite intenzionale:** su liste lunghe alcune funzioni sono quadratiche; la rappresentazione potrà cambiare senza modificare il codice Nail.

## Libreria standard scritta in Nail

`stdlib.nail` definisce `id`, `compose`, `map`, `filter`, `fold`, `reverse`, `length`. Nessuna di queste funzioni è implementata come primitiva JS. `map`, `filter` e `fold` sono già ricorsivi e di ordine superiore.

## Esecuzione e test

Con Node.js:

```sh
node v0.3/test.js
```

I file `cases.json` raccolgono 24 test positivi e 12 test negativi condivisibili con una futura implementazione PHP. `test.js` aggiunge una verifica strutturale dell'AST: **37 test** totali, verificati con Node.js 22.

Per l'uso programmatico:

```js
const { NailSeed3 } = require('./NailSeed.js');
const fs = require('node:fs');
const vm = NailSeed3.create();
vm.run(fs.readFileSync('./stdlib.nail', 'utf8'));
console.log(vm.run('map ( fun x -> x * 2 ) [ 1 , 2 , 3 ] ;'));
```

La versione JavaScript non dipende da Node per il runtime ed è pensata anche per Scriptable, ma **non è ancora stata verificata su iOS**. Il test harness usa invece Node (`assert`, `fs`).

## Limiti consapevoli

- Niente `dup`, `swap`, `rot` (non esistono operazioni stack nel linguaggio).
- Niente sections `* 2`, pipe `|>`, stringhe `s:...`, pattern matching, ADT, tipi statici o moduli.
- Niente ricorsione ottimizzata in coda: la profondità dipende dallo stack JavaScript. `maxSteps` limita il lavoro, ma non rende sicura l'esecuzione di sorgente non attendibile.
- L'ambiente globale è estensibile tra le chiamate `run`: le chiusure vedono le definizioni globali aggiunte successivamente; i parametri sono catturati lessicalmente.
- Le definizioni sono sequenziali, e in caso di errore `run` non effettua rollback delle definizioni già registrate.
- Solo JavaScript per ora: PHP tornerà dopo aver stabilizzato i test semantici.

## Prossimo esperimento

Studiare `let` locale, dati algebrici/pattern matching e una rappresentazione efficiente delle liste, **senza ampliare i cinque nodi espressivi se non necessario**. Poi costruire interprete PHP contro `cases.json` e passare dal valutatore AST a una VM o a un compilatore minimale senza bloccarci all'ISA storica.
