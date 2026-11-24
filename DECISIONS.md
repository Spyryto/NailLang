# Nail — Registro delle decisioni

Baseline: 24 novembre 2026, ramo main, release v0.60. Questo registro sintetizza le decisioni discusse; non sostituisce la [specifica](SPEC.md), le [note di release](docs/releases/0.60.md) né i test. I principi stabili sono in [PRINCIPLES.md](PRINCIPLES.md); le priorità in [ROADMAP.md](ROADMAP.md).

Stati: **adottata** = orientamento o scelta corrente; **sperimentale** = percorso non ancora promosso; **da valutare** = proposta, non impegno; **scartata come vincolo** = alternativa non obbligatoria. Ogni scelta è rivedibile.

| ID | Stato | Decisione e motivazione |
|---|---|---|
| D01 | Adottata | Haxe come host, JS/PHP come target principali: portabilità e accessibilità web; non imporre l'eliminazione di Haxe. |
| D02 | Adottata | Nucleo funzionale e sintassi regolare con token separati da spazi: parsing e manipolazione del codice semplici. |
| D03 | Adottata | AST canonico piccolo, con cinque costruttori; mantenere la rappresentazione semantica separata dall'esecuzione. |
| D04 | Adottata | Tipizzazione statica e semantica numerica Int/Ratio/Float, con esattezza di default e Float espliciti; relazioni finite esplicite per operazioni tipizzate. Vedi [SPEC](SPEC.md). |
| D05 | Adottata | Accesso ai record con `person . name`; favorire nomi locali e contesti rispetto ai prefissi. |
| D06 | Adottata | Preferire trasformatori procedurali di AST a un sistema di macro prematuramente generale; sfruttare i meccanismi già disponibili quando riducono il codice. |
| D07 | Scartata come vincolo | Compatibilità tra tutte le versioni pre-1.0 e obbligo di eseguire la versione precedente: costo non giustificato. Conservare le versioni storiche anziché accumulare compatibilità. |
| D08 | Adottata | Bootstrap progressivo e dogfooding; confronto con implementazioni Haxe indipendenti quando utile. Non imporre il self-hosting integrale. Vedi [BOOTSTRAP](docs/BOOTSTRAP.md). |
| D09 | Adottata | Import selettivi pubblici e capability grant espliciti; ABI pubblico v3 chiuso. Non confondere hash con autenticità del publisher. Vedi [HOST-CAPABILITIES](HOST-CAPABILITIES.md). |
| D10 | Sperimentale | Provider verificati, schemi HM aperti in preview, Nail-first per moduli isolati e macro locali scritte in Nail. Non promuovere automaticamente i preview a import pubblici. Vedi [0.60](docs/releases/0.60.md). |
| D11 | Adottata nel candidato | CoreIR semantica a cinque nodi, con posizioni di coda esplicite; non è bytecode ottimizzato. La provenienza sorgente completa nella IR rimane un limite. |
| D12 | Da valutare | Apertura di contesti per DSL, precedenza del contesto interno e accesso esplicito per disambiguare. Il generale `use Module { ... }` non è una feature pubblica approvata. Vedi [DSL-DESIGN](DSL-DESIGN.md) e [esperimento](docs/CONTEXT-BLOCK-EXPERIMENT.md). |
| D13 | Da valutare | Import locali o a fine file per locality of behavior; preferire forme selettive, senza complicare il parser con namespace qualificati inutili. Non confondere queste proposte con la sintassi attuale. |
| D14 | Da valutare | Interoperabilità diretta e semplice ispirata a Mira; evitare un FFI generalizzato prima dei casi concreti. Mantenere i confini di sicurezza delle capability esistenti. |
| D15 | Da valutare | Traspilatori sorgente JS/PHP e backend PHX-VM. PHX-VM resta un progetto indipendente; nessuna integrazione attuale è presupposta. |
| D16 | Adottata | Correttezza prima delle ottimizzazioni; misurare separatamente compilazione, esecuzione e CI. Haxe/JS può sostituire --interp nei job quando vantaggioso senza ridurre le verifiche. |
| D17 | Adottata | Language tour, cookbook, lookbook e documentazione storica; Nail Lab come ambiente interattivo complementare. |
| D18 | Scartata come vincolo | Minimalismo assoluto: una primitiva o un costrutto View è ammissibile se semplifica davvero l'implementazione. La necessità concreta di View resta da valutare. |
| D19 | Adottata | Confronto evolutivo permanente con Dart e F#: Dart come riferimento pratico, F# come riferimento funzionale e di tipizzazione. Aggiornare le ricette e le lacune pertinenti senza imporre parità di feature. Vedi [COOKBOOK-FSHARP](COOKBOOK-FSHARP.md). |
| D20 | Adottata nel candidato 0.61 | `data . name` senza annotazione inferisce un requisito strutturale aperto (`{name:a | r} -> a`); `( data : Person )` richiede il tipo nominale `Person`. Il controllo usa le righe aperte già presenti e fissa le annotazioni prima dell'inferenza, senza conversioni di valori o ABI nuovi. Il compilatore pubblico rifiuta ancora l'export di schemi aperti. Vedi la suite `structural-projection` (Haxe/JS/PHP). |

## Alternative da non reintrodurre senza motivazione

- Compatibilità obbligatoria tra versioni sperimentali.
- Self-hosting perseguito a prescindere da costi e vantaggi.
- Macro sofisticate, nuove istruzioni VM o astrazioni generali introdotte senza un caso d'uso.
- Ottimizzazione prematura che perda informazione semantica.
- Import ambienti impliciti o esecuzione diretta di provider non verificati nel percorso pubblico corrente.

## Come aggiornare il registro

Per una nuova scelta annotare ID, stato, contesto, decisione, alternative, motivazione, costi/limiti e riferimento a test, commit o PR quando disponibile. Se una scelta cambia, segnalarla come superata e collegare la nuova decisione anziché riscrivere la storia. Il registro iniziale è una sintesi delle discussioni, non una ricostruzione esaustiva di tutti i commit.
