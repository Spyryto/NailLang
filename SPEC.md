# NailSeed 0.1 — protocollo sperimentale

NailSeed è un esperimento di nucleo concatenativo funzionale, ispirato ai principi di Joy e Forth. Questa non è ancora la specifica definitiva del linguaggio Nail né un sostituto per NailVM 0.1.

## Obiettivi

- Testo sorgente a token delimitati **sempre** da whitespace. Delimitatori `[` e `]` sono token separati.
- Parser portabile e piccolo (tokenizer + lettura ricorsiva di quotations).
- Composizione di programmi come operazione fondamentale.
- Programmi come valori immutabili (quotations), con esecuzione, composizione e cattura di valori.
- Funzioni ordinarie pure, con `def` consentita solo al livello superiore.
- Test di conformità condivisi fra JavaScript e PHP.

## Lessico minimo v0.1

| Sorgente | Semantica |
|---|---|
| `123` / `-2` / `3.14` | numero |
| `true` / `false` | booleano |
| `s:Ciao%20mondo` | stringa `Ciao mondo` (percent-encoding) |
| `:square` | simbolo letterale `square` |
| `square` | invoca la parola `square` |
| `[ 1 + ]` | quotation (programma non eseguito) |
| `# commento` | commento fino alla fine della riga, con `#` token separato |

Non esistono precedenze di operatori, indentazione significativa, parentesi attaccate o stringhe con spazi non codificati.

## Effetti di stack (notazione descrittiva, non ancora verificata staticamente)

- `dup`: `( ...S a -- ...S a a )`
- `swap`: `( ...S a b -- ...S b a )`
- `+`: `( ...S Number Number -- ...S Number )`
- `call`: `( ...S Quote -- ...T )`, in base all'effetto della quotation
- `dip`: `( ...S a Quote -- ...T a )`, eseguendo la quotation sullo stack senza `a`
- `compose`: `( ...S Quote Quote -- ...S Quote )`
- `curry`: `( ...S a Quote -- ...S Quote )`, cattura un valore immutabile
- `if`: `( ...S Bool Quote Quote -- ...T )`, esegue il primo ramo se true
- `pack`: `( ...S item1 ... itemN N -- ...S List )`
- `map`: `( ...S List Quote -- ...S List )`, la quotation trasforma un elemento in uno
- `fold`: `( ...S List init Quote -- ...S result )`, la quotation trasforma `(acc, x)` in `acc`
- `def`: `( ...S Symbol Quote -- ...S )`, **solo top-level**, nome non già occupato

Le parole degli utenti non possono ridefinire parole esistenti. I dati-lista sono consumati senza mutazioni del loro contenuto. La macchina, come ogni interprete a stack, usa uno stack mutabile internamente, ma le trasformazioni di programma sono pure tranne l'installazione di parole al top-level.

`=` in questa versione compara solo valori scalari, non liste o quotations.

## Esempi validati in JS e PHP

```text
:square [ dup * ] def
:inc [ 1 + ] def
5 inc square           # 36

:twice [ dup [ call ] dip call ] def
5 [ 1 + ] twice        # 7

:fact [ dup 2 < [ drop 1 ] [ dup 1 - fact * ] if ] def
5 fact                 # 120

1 2 3 3 pack [ dup * ] map     # [ 1 4 9 ]
1 2 3 3 pack 0 [ + ] fold      # 6
3 5 [ + ] curry call           # 8
```

## Esecuzione

- Node.js: `node NailSeed-0.1.js`. Come libreria: `const NailSeed = require('./NailSeed-0.1.js'); const vm = NailSeed.create(); vm.run('3 4 +');`.
- Scriptable: copiare il sorgente JS in uno script e avviarlo; usa soltanto JavaScript standard e `console.log`; la compatibilità reale con Scriptable non è ancora stata collaudata sul dispositivo.
- PHP 8: `php NailSeed-0.1.php`. Da altro file: `require 'NailSeed-0.1.php'; $vm = new NailSeed(); $vm->run('3 4 +');`.
- Entrambi gli script, eseguiti direttamente, eseguono **11 test** e mostrano un messaggio per ciascuno.

## Cosa NON è ancora

- Non c'è inferenza dei tipi, né un controllo statico degli effetti di stack.
- Non ci sono ADT, pattern matching, moduli o codice macro interamente nel linguaggio.
- Non è self-hosting: definisce nuove parole e combinatori, ma non interpreta autonomamente stringhe sorgente o compila autonomamente il proprio codice.
- Non sono ancora disponibili host calls, gestione esplicita IO, isolamento dei permessi o sandbox di produzione.
- L'esecuzione è ricorsiva sull'host, quindi non dispone ancora di trampoline o tail-call garantito; è presente un limite di passi per chiamata.
- La semantica deve essere ulteriormente testata sui casi-limite di numeri e Unicode, prima di considerare i due backend del tutto equivalenti.

## Prossimo incremento architetturale suggerito

1. Congelare una piccola suite di test condivisa con casi normali e negativi.
2. Aggiungere valori algebrici `tag` / `record`, operazioni primitive su liste e quotations come dati e una forma di `match`.
3. Spostare `map`, `fold`, controllo di flusso e libreria standard da primitive native a definizioni Nail, dove possibile.
4. Scrivere in Nail un tokenizer/parser di Nail (self-hosting dello strato sintattico), poi il compilatore verso un bytecode astratto.
5. Studiare la compatibilità fra la rappresentazione di quotations e la precedente ISA NailVM 0.1 (`CLOS/CALL`, `REC/GET`, `TAG/CASE`, `PRIM/HOST`), senza rompere la VM esistente.
6. Aggiungere type inference con variabili di riga di stack, tipi algebraici e distinzione degli effetti di IO; mantenere il core puro.
7. Solo dopo la stabilizzazione valutare Haxe come singola implementazione sorgente compilabile in JS/PHP, conservando gli stessi test di conformità.