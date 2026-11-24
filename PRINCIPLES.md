# Nail — Principi guida

Questi principi orientano il progetto, non costituiscono una specifica del linguaggio.
Le scelte concrete sono registrate in [DECISIONS.md](DECISIONS.md); il lavoro futuro in [ROADMAP.md](ROADMAP.md).

## Filosofia
- Ricercare semplicità, eleganza, ortogonalità e componibilità, non minimalismo a tutti i costi. Una primitiva aggiuntiva è benvenuta se semplifica significativamente il sistema.
- Costruire bottom-up, ispirandosi a Forth: poche primitive solide, astrazioni ottenute per composizione. Trarre ispirazione anche da ML, F#, Scheme e AliceML senza imitarli obbligatoriamente.
- Introdurre complessità soltanto quando necessaria o significativamente vantaggiosa; segnalarne motivazione, costi e carattere eventualmente provvisorio.
- Preferire meccanismi generali quando sono realmente più semplici; evitare astrazioni speculative. Verificare periodicamente se le nuove capacità permettano di ridurre l'implementazione.

## Linguaggio e architettura
- Privilegiare sintassi tersa, regolare, espressiva e facilmente parsabile; evitare zucchero sintattico privo di benefici concreti.
- Favorire programmazione funzionale, composizione, immutabilità dove appropriata, sicurezza statica dei tipi, locality of behavior, nomi significativi e DSL.
- Mantenere piccolo e manipolabile l'AST canonico. Trattare il codice come dati trasformabili; preferire trasformazioni procedurali quando più semplici di meccanismi sofisticati.
- Separare parsing, trasformazioni, controllo dei tipi, rappresentazioni semantiche e strategie esecutive. Preservare significato, binding e provenienza sorgente lungo le trasformazioni.
- Disaccoppiare il linguaggio dai backend; non sacrificare l'informazione semantica per ottimizzare prematuramente.
- Favorire interoperabilità semplice ed esplicita con l'host, senza reinventarne le funzionalità né introdurre strati gratuiti. Mantenere il nucleo indipendente dalle API specifiche.

## Evoluzione e implementazione
- Il dogfooding è fondamentale: utilizzare Nail per costruire Nail e il suo tooling, osservando benefici e limiti delle nuove feature.
- Il bootstrap e il self-hosting sono strumenti, non fini assoluti. Usare Haxe quando conveniente; mantenere implementazioni indipendenti di riferimento quando utili alla correttezza.
- Nessuna retrocompatibilità garantita prima della 1.0; non richiedere che ogni versione possa eseguire la precedente. Conservare tag, documentazione e toolchain storiche.
- Procedere per piccole iterazioni verificabili. Essere disposti a rimuovere feature e ripensare scelte precedenti.
- Distinguere decisioni, esperimenti e proposte. Non cambiare la roadmap per inseguire ogni nuova idea.

## Correttezza, prestazioni e verifica
- La correttezza non è negoziabile. Privilegiare semplicità ed espressività; ottimizzare sulla base di misure e casi d'uso reali.
- Distinguere costo di compilazione, esecuzione, bootstrap e CI. Consentire backend specializzati senza compromettere le rappresentazioni canoniche.
- Verificare i target supportati (in particolare JS e PHP), le regressioni e il bootstrap quando pertinente. Non eliminare verifiche per accelerare la CI.
- Usare gli strumenti Haxe più convenienti (incluso il target JS in alternativa a --interp) e parallelizzare i job quando utile. Separare refactoring, nuove feature e ottimizzazioni quando possibile.
- Non dichiarare pronta una release senza aver verificato i gate pertinenti sul commit finale.

## Obiettivi applicativi
- GUI e UI web dichiarative, componenti, MVU e DSL.
- Programmazione network-aware: comunicazione client-server, bridge solidi e tipizzati, richieste asincrone e parallelismo attraverso le capacità dell'host (ad esempio Web Workers e AMPHP).
- Riduzione, attraversamento e trasformazione di strutture dati; metaprogrammazione e tooling.
- Sviluppo accessibile anche da browser e dispositivi mobili.
- Privilegiare questi casi d'uso rispetto al number crunching fine a sé stesso. Sono obiettivi, non promesse di funzionalità già disponibili.

## Documentazione e apprendimento
- Documentare il come e il perché delle implementazioni, incluse le alternative scartate e i loro trade-off.
- Mantenere un confronto continuo con Dart (uso pratico) e F# (programmazione funzionale, tipi, composizione e astrazioni). Aggiornare cookbook e lookbook pertinenti a ogni modifica significativa; distinguere equivalenze, limiti e proposte, senza imitare automaticamente i linguaggi di riferimento.
- Conservare la storia evolutiva, il language tour per versione, il cookbook eseguibile e il lookbook delle funzionalità mancanti o componibili.
- Favorire documentazione viva, diagrammi, esempi reali e strumenti interattivi; rendere ispezionabili AST, trasformazioni, IR ed esecuzione.
- Nail Lab è un ambiente complementare di studio, REPL e sperimentazione. Nail è anche un laboratorio per comprendere l'architettura dei linguaggi.
