# NailSeed v0.5 — inferenza statica senza nuove forme AST

## Obiettivo

Conservare **esattamente cinque** costruttori di espressioni (`Literal`, `Var`, `Lambda`, `Apply`, `If`) e tutti i 37 test della v0.4. Aggiungere un **passaggio separato** di inferenza Hindley–Milner per controllare il sorgente e dedurre firme di funzione, senza annotazioni manuali.

## Sistema dei tipi

```
Type = Number | Bool | [Type] | Type -> Type | Variable
Scheme = forall variables. [Eq constraints] Type
```

I tipi funzione sono associativi a destra. `Number` indica il numero float finito del runtime, non un intero separato. Tutte le liste hanno elementi omogenei; `[]` è polimorfa.

Esempi:

```
def twice x = x * 2 ;          # Number -> Number
def id x = x ;                # forall a. a -> a
def compose f g x = f ( g x ) ;
                                  # forall a b c. (a -> b) -> (c -> a) -> c -> b
def same x y = x == y ;       # forall a:Eq. a -> a -> Bool
```

I `def` sono trattati come `letrec` di alto livello: durante l'analisi del corpo il nome è disponibile, ma con un **solo tipo monomorfo provvisorio**. Terminato il corpo, quel tipo viene generalizzato nei parametri non liberi nell'ambiente esterno.

La v0.5 **non** implementa polymorphic recursion né `let` locale; l'applicazione parziale segue il currying del nucleo.

## Regole di inferenza

- `Literal`: `Number`, `Bool` o lista di un tipo fresco `a` (per `[]`).
- `Var`: istanzia le variabili quantificate nella `Scheme` associata al nome.
- `Lambda`: introduce un tipo fresco monomorfo per il parametro.
- `Apply`: unifica `type(fn)` con `type(arg) -> freshResult`.
- `If`: la condizione deve avere tipo `Bool`; i rami devono unificarsi.
- `Def`: preassegna il nome ricorsivo a una variabile di tipo fresca, inferisce il corpo, unifica e generalizza.

`+`, `-`, `*`, `/` hanno tipo `Number -> Number -> Number`. I confronti `<`, `<=`, `>` e `>=` sono `Number -> Number -> Bool`. `cons`, `head`, `tail`, `isEmpty`, `nil` e la primitiva privata `#cons` hanno firme polimorfe parametriche.

`==` e `!=` hanno tipo `forall a:Eq. a -> a -> Bool`, dove i tipi `Eq` sono ricorsivamente `Number`, `Bool` e `[Eq]`. Non si può confrontare una funzione, anche se Haxe o JavaScript permetterebbero un confronto per identità.

## Algoritmo e limiti

Unificatore con sostituzioni e occurs check (rifiuta `fun x -> x x`). Ogni sessione di `TypeChecker.check` lavora su una copia delle firme globali e le aggiorna soltanto al successo dell'intero programma. Un identificatore progressivo evita collisioni tra chiamate incrementali. Le `Scheme` salvate sono normalizzate: non dipendono dalle sostituzioni di sessioni precedenti.

`TypeChecker.signature(name)` restituisce la firma inferita delle definizioni. `TypeChecker.preview()` permette analisi senza mutare il checker, e `TypeChecker.copy()` permette fork temporanei. Il TypeChecker è isolato dalla VM: **controllare non significa eseguire**. Le prove di regressione originali restano eseguibili su `Vm.run()` senza variazioni.

### Limiti consapevoli

- Nessuna inferenza degli effetti, verifica di totalità o controllo dei casi esaustivi; `head []` resta un errore runtime.
- Niente tipi ricorsivi, polimorfismo ricorsivo o varianti algebriche utente.
- Niente tipi `Int`, `Float` separati, record o strutture dei moduli.
- Niente local `let`: `def` resta una forma top-level.
- Niente ottimizzazione tail-call: la VM rimane ricorsiva e dipendente dallo stack host.
- Le API restano sperimentali: nessun formato di serializzazione dei tipi né informazioni source-span.

## Compilazione

Il sorgente unico è Haxe 4.3.7. Il workflow `.github/workflows/nailseed-v05.yml` testa inferenza + runtime su `--interp`, JS/Node e PHP, poi compila i distributable. Le compilazioni JS/PHP non vengono committate nel repository: sono artefatti CI.
