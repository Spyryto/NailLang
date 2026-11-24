# Nail — Roadmap

Aggiornamento iniziale: 24 novembre 2026. La roadmap è rivedibile e non promette date né numeri di versione oltre quelli già documentati. Vedi [PRINCIPLES.md](PRINCIPLES.md) e [DECISIONS.md](DECISIONS.md).

## 1. Priorità immediata: consolidare 0.60

La [release v0.60](https://github.com/Spyryto/NailLang/releases/tag/v0.60) è stata pubblicata il 24 novembre 2026 sul commit `afa5400a`, dopo i controlli richiesti. Le milestone 0.56–0.59 non sono release autonome. I lavori successivi su `main` non modificano gli artefatti già pubblicati.

- [x] Verificate sul commit di release le suite Haxe/JS/PHP, macro, type checker, moduli e CoreIR.
- [x] Verificati i bundle source-free, l'esclusione dello stage zero e lo smoke di `nail 0.60 ;` su JS e PHP.
- [x] Pubblicata v0.60 tramite il [workflow di release](https://github.com/Spyryto/NailLang/actions/runs/45374966717) dopo test e packaging riusciti.
- [x] Registrati i limiti rimasti nelle [note della 0.60](docs/releases/0.60.md), senza ottimizzazioni estranee alla verifica.

Le note 0.60 sono la fonte specifica dei gate: questo documento non le modifica. La [CI completa sul commit di release](https://github.com/Spyryto/NailLang/actions/runs/45374966656) ha superato tutti i nove job richiesti.

## 2. Consolidamento dopo 0.60 — proposte da ordinare dopo i gate

- Valutare la riduzione di codice e la semplificazione delle parti Nail/Haxe, usando dogfooding dove vantaggioso.
- Consolidare diagnostica e provenienza sorgente lungo le trasformazioni e la CoreIR.
- Valutare quando promuovere i percorsi sperimentali Nail-first e macro locali, senza rimuovere prematuramente gli oracoli indipendenti.
- Esaminare i casi reali di interoperabilità e di composizione modulare: partire da import/capability già esistenti, non da un nuovo sistema generale.
- Ampliare esempi verificabili e Nail Lab, così da usare il linguaggio e studiarne l'architettura anche da browser.

Queste voci sono una proposta di ordinamento, non una nuova roadmap di release approvata.

## 3. Esplorazioni a medio termine (non assegnate a una versione)

| Area | Esperimento / risultato atteso |
|---|---|
| DSL e UI | Verificare apertura dei contesti, disambiguazione, componenti e MVU su piccole app reali; valutare View solo se utile. |
| Interoperabilità | Esempi JS/PHP concreti, bridge tipizzati, confronto con la semplicità di Mira. |
| Network-aware | Richieste asincrone e composizione; eventuali Web Workers e AMPHP via host, con semantica esplicita. |
| Tooling | Analisi del sorgente, diagnostica con riga/colonna, REPL, editor e ispezione AST/IR; valutare un language server in Nail quando sostenibile. |
| Backend | Valutare traspilazione JS/PHP e integrazione eventuale di PHX-VM a partire da una IR semantica; misurare prima di scegliere. |
| Prestazioni | Benchmark riproducibili di compilazione, esecuzione, bootstrap e CI, su workload rilevanti; ottimizzazioni mirate dopo la correttezza. |

## 4. Verso 1.0

Prima di dichiarare stabilità, definire la specifica pubblica e i confini di compatibilità, testare i target dichiarati, consolidare interoperabilità, documentazione e distribuzione, e rivedere le astrazioni introdotte. Nessuna compatibilità è garantita prima della 1.0.

## Regola di avanzamento

Ogni iterazione deve dichiarare obiettivo, risultato osservabile, verifica e limiti. Una nuova idea entra nel registro delle decisioni o nel backlog prima di modificare le priorità correnti. I gate concreti restano nelle note della release pertinente.
