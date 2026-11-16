# Nail Language Tour — v0.39

[Indice delle versioni](./docs/versions.md) · [Cookbook](./COOKBOOK.md) · [Esecuzione](./RUNNING.md) · [Specifiche host](./HOST-CAPABILITIES.md)

**Novità della v0.39:** capability di scrittura del testo separate dalle letture, con autorizzazione esplicita dell'host e risultati tipizzati `CoreResult`. La grammatica Nail e la VM non acquisiscono un accesso implicito ai file.

## Primo programma

```nail
def twice x = x * 2 ;
twice 21 ;
```

Risultato: `42`. Nail applica funzioni per giustapposizione e richiede token separati da spazi. Le funzioni sono currificate:

```nail
def add a b = a + b ;
def addTen = add 10 ;
addTen 32 ;
```

## Collezioni, record e somme

```nail
map ( fun x -> x * 2 ) [ 1 , 2 , 3 ] ;
type Person { name Text age Number } ;
( Person " Ada " 32 ) . age ;
```

I record hanno accesso `value . field`; le somme algebriche si analizzano con `match`. Il tipo standard `CoreResult[ok,err]` ha due costruttori: `CoreOk` e `CoreErr`.

## Scritture: dichiarare l'intenzione non concede il permesso

```nail
def save key contents =
  match writeAsset key contents with
  | CoreOk savedKey -> savedKey
  | CoreErr reason -> reason ;
```

`writeAsset` **non è una primitiva globale**. Deve essere concesso da un'applicazione ospite; un modulo compilato richiede esplicitamente `NailHost.writeTextResult` con firma:

```text
Text -> Text -> CoreResult[Text, Text]
```

Il primo `Text` è un identificatore di risorsa autorizzato dall'host, il secondo è il contenuto sostitutivo. Un modulo con solo `readTextResult` non ha automaticamente il permesso di scrivere. Gli errori previsti arrivano come `CoreErr`, non come eccezioni dell'host esposte al codice Nail.

## Come provarlo

1. Esegui il [cookbook](./COOKBOOK.md) per valori, funzioni e liste.
2. Consulta [RUNNING.md](./RUNNING.md) per compilare JS/PHP ed eseguire la demo browser.
3. Per gli effetti host, leggi `src/nail/TextWriteCapability.hx`, `src/nail/HostTextGrants.hx` e [HOST-CAPABILITIES.md](./HOST-CAPABILITIES.md).
4. Esegui i test `host-text-writes-test-*.hxml` sui tre target: coprono separazione dei privilegi, quote, codici d'errore, VM AST, bytecode e bootstrap.

**Limite fondamentale:** la sostituzione atomica è un *contratto* richiesto alla callback dell'host. Nail non garantisce la transazionalità di un filesystem o la durabilità di una scrittura; la v0.39 non fornisce un adattatore file/rete.

Le versioni fino a v0.38 restano consultabili dai rispettivi tag. Il runtime Haxe compilato espone ancora il nome API `NailSeed` in JS per compatibilità.
