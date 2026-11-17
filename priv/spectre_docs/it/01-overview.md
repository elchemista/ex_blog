# Documentazione Spectre 0.4

Costruisci agenti che riconoscono richieste, usano modelli e strumenti ed eseguono lavoro governato in processi Elixir supervisionati.

Spectre separa riconoscimento, proprietà della conversazione e permesso di agire. Un modello può aiutare a comprendere una domanda, generare testo o preparare una proposta. L'applicazione decide quali operazioni esistono, chi può autorizzarle, come persiste lo stato e cosa costituisce un risultato osservato.

## Parti dall'architettura

```text
Stack                         Agent                         Server
capacità installate      →    route e intenti         →    callback applicative
modelli, memoria, tool        prove di riconoscimento       conversazione + worker
                                                                  │
                                               proposta governata │
                                                                  ▼
                                                        Managed GAM
                                                 autorità + consenso umano
                                                                  │
                                                     Act ammesso → esecuzione
                                                                  │
                                                         Outcome osservato
```

**Stack** seleziona le capacità riutilizzabili. **Agent** dichiara il riconoscimento. **Server** possiede la conversazione in esecuzione attraverso normali callback OTP. Le Skill montate hanno processi Server e stato propri, condividendo il Domain GAM dell'agente principale.

**GAM significa Governed Act Model.** Definisce il passaggio da una proposta a un'operazione autorizzata. Ammissione ed esecuzione sono fatti distinti: il permesso di inviare un'email non dimostra che il servizio l'abbia accettata. Leggi il [manifesto GAM](/it/governed-act-model), poi la [guida all'architettura](/it/docs/architecture-gam).

## Scegli un percorso

| Obiettivo | Guida |
| --- | --- |
| Avviare la prima conversazione senza modello o database | [Primi passi](/it/docs/getting-started) |
| Comprendere proprietà, worker e approvazione | [Architettura e GAM](/it/docs/architecture-gam) |
| Combinare pattern, similarità e classificazione con modelli | [Routing](/it/docs/routing) |
| Verificare esempi, generare embedding e addestrare un classificatore | [Training](/it/docs/training) |
| Chiedere consenso a una persona attraverso un altro agente | [Comunicazione tra agenti](/it/docs/agent-to-agent) |
| Implementare un provider o un'integrazione applicativa | [Behaviour](/it/docs/behaviours) |
| Persistere la storia, ridurre la RAM storica e recuperare | [Storage](/it/docs/storage) |
| Generare e diagnosticare un'applicazione | [Task Mix](/it/docs/mix-tasks) |
| Scegliere librerie opzionali | [Ecosistema](/it/docs/ecosystem) |
| Costruire un flusso completo | [Ricette](/it/docs/recipes) |
| Verificare comportamenti e gestire il sistema | [Test e produzione](/it/docs/testing-production) |
| Aggiornare un'applicazione esistente | [Migrazione dalla 0.3](/it/docs/migration) |

## Requisiti

Il core richiede Elixir `~> 1.19` e funziona senza modelli o database. Aggiungi `{:spectre, "~> 0.4.0"}` alle dipendenze. Modelli, driver del browser, credenziali dei trasporti e pool del database sono dipendenze dell'applicazione, installate solo quando servono.

Le nove librerie satellite sono opzionali. Il core non ne ha bisogno per compilare, eseguire i propri test o avviare un AgentServer in RAM. Le versioni dei satelliti sono indipendenti: consulta le [note di installazione dell'ecosistema](/it/docs/ecosystem) prima di copiare le dipendenze.

## Come leggere gli esempi

La prima guida contiene un esempio completo senza modelli. I frammenti successivi indicano Stack, provider, prompt o registrazioni degli effetti necessari. Nomi come `MyApp.Embeddings`, `MyApp.PrivateArchive` e `MyApp.MailClient` rappresentano adapter applicativi; non sono moduli forniti da Spectre.

Le guide descrivono il **percorso AgentServer della 0.4**. Le API precedenti `Instance`, `Run`, Work/Vigil ed evoluzione delle definizioni restano documentate per le applicazioni esistenti, ma non sostituiscono il ciclo di vita del nuovo Server. Consulta il [riferimento API versionato](https://hexdocs.pm/spectre/0.4.0/) per i tipi esatti e le [guide sorgente della 0.4](https://github.com/elchemista/spectre/tree/0.4.0/docs) per gli esempi eseguibili.
