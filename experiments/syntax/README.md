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
già dichiarata nello stesso file. Gli argomenti forniti vengono catturati
una volta nell'ordine in cui sono scritti. I parametri non forniti
rimangono lambda curried nell'ordine originale di dichiarazione.

`value >> fn` si riduce a `fn value`. È associativo a sinistra e ha
precedenza inferiore a operatori aritmetici e confronti. Un nome con
trattino come `add-one` è un identificatore intero; la sottrazione
mantiene `a - b` con spazi intorno.

## Modalità esplicita

Nel codice Haxe che ospita Nail:

```haxe
var vm = new nail.Vm();
var result = vm.runPlainExperimental(source);
```

Il normale `vm.runPlain(source)` e `new Parser(source)` **non attivano**
questa sintassi. Il parser rimane quello Haxe e il bootstrap scritto in
Nail non conosce ancora le nuove forme.

## Confini, da verificare prima di ogni promozione

- Identificatori composti stile `def set contains: item in: entries`
  **non** sono ancora supportati. Mancano le regole di risoluzione dei nomi.
- Le label sono disponibili soltanto per definizioni locali già viste,
  non ancora per import, extern o funzioni della stdlib.
- Le keyword richiedono il `:`: `item: 2`, non `item 2`.
- La punteggiatura richiede ancora spazi intorno ai token.
- Il type checker completo e il bootstrap Nail v0.61 non usano ancora
  questo percorso. Non dichiarare che la nuova superficie sia già
  analizzabile tipicamente o disponibile in Nail Lab.
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
