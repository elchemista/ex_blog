# Migrare dalla 0.3 alla 0.4

Migra consapevolmente proprietà della conversazione ed esecuzione degli effetti, mantenendo dove necessario le integrazioni compatibili del runtime precedente.

Spectre 0.4 cambia dichiarazione degli agenti, proprietà delle conversazioni ed esecuzione dei tool nelle nuove applicazioni. Mantiene riconoscimento, esempi etichettati, training, adapter dei provider e composizione Stack. Un'applicazione Instance non diventa AgentServer aggiornando soltanto la dipendenza.

Scegli una route che in 0.3 produce solo testo. Nella 0.4 mantieni la dichiarazione nell’Agent e sposta la risposta in `handle_flow({flow, label}, input, ctx)` nel Server. Verifica la risposta al consumer, poi migra un’operazione con effetto usando [proposta, consenso e continuazione](/it/docs/handlers).

## Mappa le responsabilità applicative

| Modello precedente | AgentServer 0.4 |
| --- | --- |
| Il DSL della route contiene l'esecuzione | Agent dichiara route; Server implementa `handle_flow/3` |
| Instance possiede il ciclo Run/Turn | Server.Runtime possiede Context, worker, attese e continuazioni |
| L'host orchestra `turn`/`execute` | Chiama `input`, restituisce Context con comandi, riceve risultati asincroni |
| `reply`, `reason`, `act` nei blocchi route | `respond`, `generate`, `propose` nelle callback Server |
| DSL di policy intorno alle azioni protette | Effetti registrati, Managed GAM, `handle_action` e `handle_pending` |
| `learn: true` | `collect_intent: true` con policy di revisione |
| Esempi `embedding:` sulla route | `semantic_examples:` |
| `via`, `:classifier`, `:semantic_cache` | `strategies`, `:local_classifier`, `:intent_dataset` |
| Checkpoint Instance e continuazione Run | Checkpoint/outbox Server e storia canonica GAM |

I nomi precedenti restano alias dove documentato; combinazioni in conflitto falliscono. Il vecchio `:llm` non abilita la classificazione LLM. Nel nuovo codice usa i nomi canonici.

## Migra prima un flusso

Mantieni lo Stack; sposta il riconoscimento in Agent e il comportamento applicativo in Server. `mix spectre.gen.agent MyApp.SupportAgent --server --dry-run` mostra la struttura corrente. Segui i [primi passi](/it/docs/getting-started), poi ricollega esplicitamente modelli e tool.

Sposta input assenti/ambigui in `handle_flow(:unmatched, input, ctx)`. Usa `generate(..., on_result: tag)` e `handle_result(tag, {:generated, response}, ctx)`. Il tag di continuazione non dichiara una route. Le callback OTP native mantengono le tuple, con Context come stato.

Dati portabili negli assigns, handle locali nel private e I/O lungo nei worker. Inizializza lo stato recuperato senza sostituirlo. Le Skill montate hanno processi Server/checkpoint propri, condividendo l'autorità GAM del root.

## Ricollega le conseguenze attraverso GAM

Elenca operazioni che accedono a risorse protette, divulgano dati, consumano risorse o modificano il mondo. Registra gli adapter e abilita nomi concreti in `gam.operations`. Aggiungi `confirm: true` quando serve. Sposta controlli di business in `handle_action/2` e conversazione in `handle_pending/3`.

Installare un tool, riconoscere una route protetta o ottenere alta confidenza non autorizza un effetto. Segnala successo osservato tramite `outcome.status == :succeeded`; conserva gli esiti incerti per la riconciliazione. Se navigare richiede consenso, copri Lens open e look basato su URL.

I selettori `authority: :development` e le tuple con host GAM manuale delle prime anteprime 0.4 sono sostituiti dalla configurazione Managed GAM. Le chiavi d'identità correnti sono `subject`, `conversation`, `task`, `tenant`, `org` e `organization`. Tieni credenziali e attributi di business estranei fuori dall'identità.

## Non reinterpretare i fatti persistenti precedenti

Non esiste un convertitore generale da checkpoint Instance a checkpoint Server. Scegli un confine di migrazione applicativo, conserva i vecchi record, riconcilia effetti in corso e traduci deliberatamente lo stato portabile. Un vecchio “sì” pendente non può essere trasformato in nuovo consenso GAM.

I checkpoint Server fissano fingerprint di compatibilità di applicazione/tool. Le modifiche possono richiedere un migratore esplicito. Non eliminare fingerprint e non ripetere effetti non ripetibili per far funzionare il recovery. Aggiornare lo schema di proiezione richiede una migrazione; passare da disco a Ledger non converte automaticamente la storia.

Un provider unificato può implementare `Spectre.Server.Store` con storia completa e proiezione opzionale. Gli adapter standalone esistenti restano supportati. `reset/2` inizializza una nuova sessione; `recover_storage/2` mantiene lo stato applicativo recuperando/sostituendo lo storage GAM. Nessuno cancella effetti già avvenuti o memoria esterna.

## Verifica l'applicazione risultante

Copri riconoscimento deterministico e semantico, modelli diversi per classificazione/generazione, esempi verificati senza vettori, compatibilità vettoriale, consolidamento dello streaming e tutti gli helper. Testa presentazione/rifiuto/scadenza del consenso, duplicati, riavvio durante un effetto, guasti DB e isolamento dopo reset.

Mantieni Work/Vigil, Instance/Run o riflessione sul percorso documentato finché non ne migri deliberatamente le responsabilità. Le API pubbliche compatibili non rendono i vecchi formati di checkpoint intercambiabili con lo stato Server.

Il [riferimento completo di migrazione](https://github.com/elchemista/spectre/blob/0.4.0/docs/MIGRATING_TO_0_4.md) contiene i dettagli. Usa il [catalogo testato dell'ecosistema](/it/docs/ecosystem) e i [controlli di produzione](/it/docs/testing-production) prima di aggiornare un deployment attivo.
