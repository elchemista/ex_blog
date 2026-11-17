# Storage, riservatezza e recovery

Lavora in RAM oppure configura coordinamento persistente, storia canonica GAM e proiezioni su database tramite un provider.

## Scegli la modalità di persistenza

| Configurazione in `gam:` | Comportamento |
| --- | --- |
| `storage: :ephemeral` | Default in sola RAM; niente database o Ledger obbligatori |
| `storage: {:disk, path}` | Autorità e storia persistenti locali; percorso distinto gestito dall'applicazione |
| `storage: :ledger` | Scopre la risorsa Ledger configurata o il provider di storia selezionato |
| `storage: {MyApp.Storage, reference}` | Un provider `Spectre.Server.Store` per coordinamento e gruppo completo della storia |

Installare Ledger non seleziona automaticamente un database, non crea tabelle e non cifra i contenuti. L'applicazione avvia il Repo e applica le migrazioni. Ogni agente/sessione logica deve avere `identity` distinta e stabile: definizione Agent e identità selezionano il namespace di Domain/checkpoint. L'`id:` del figlio nel supervisor non separa i record del database.

## Tre risorse, un contratto di provider

Il **coordinamento** conserva checkpoint revisionati, inbox/outbox e stato dei comandi. La **storia canonica GAM** registra batch completi append-only. La **proiezione** è un modello di lettura indicizzato e ricostruibile dalla storia verificata.

Un database personalizzato implementa `Spectre.Server.Store` e viene configurato una sola volta:

```elixir
{:ok, server} = Spectre.Server.start_link(
  agent: MyApp.SupportAgent,
  identity: %{tenant: "acme", subject: "customer-42", conversation: "support"},
  consumer: self(),
  gam: [storage: {MyApp.Storage, MyApp.Repo}]
)
```

`MyApp.Storage` e `MyApp.Repo` sono moduli applicativi, non client incorporati. Il riferimento del provider è il primo argomento delle callback. Spectre non avvia un secondo provider e non ferma un pool condiviso quando si chiude un agente.

| Gruppo | Callback |
| --- | --- |
| Coordinamento | Richieste `fetch/2`, `put_new/3`, `compare_and_swap/4`, `delete/3`; `list/3` opzionale e limitata |
| Storia canonica | Gruppo completo `ledger_append/6`, `ledger_load/3`, `ledger_head/3`, `ledger_read_batch/4`, `ledger_lookup_batch/4`, `ledger_export/3`; `ledger_load_from/4` opzionale |
| Proiezione storica | Tutte e sei `projection_open/3`, `projection_head/3`, `projection_commit/6`, `projection_fetch/5`, `projection_page/5`, `projection_select/6`, oppure nessuna |

Fetch restituisce `{:ok, %{revision: revision, value: value}}`, `:not_found` o errore. Le scritture acquisiscono revisioni atomicamente; CAS e cancellazione controllano la revisione attesa. Gli append acquisiscono batch completi e deduplicano l'identità del batch. Una conferma di scrittura incerta resta `{:error, :ambiguous}`. Righe della proiezione e cursore avanzano atomicamente, con protezione per generazione e letture al cursore esatto. Sono barriere di persistenza distinte, non una transazione automatica fra tre store.

Vedi [fixture completa del provider unificato](https://github.com/elchemista/spectre/blob/0.4.0/test/server/unified_store_test.exs) e [tipi delle callback](/it/docs/behaviours). Gli adapter standalone `GAM.Ledger.Store` e `Domain.Projection.Store` restano compatibili.

## PostgreSQL tramite Ledger

Installa Ledger compatibile, `ecto_sql` e `postgrex`, supervisiona il Repo, installa Ledger nello Stack e configura la risorsa del runtime:

```elixir
{Spectre.Stack.Runtime,
 stack: MyApp.AI,
 name: MyApp.AIRuntime,
 packages: [spectre_ledger: [server_store: [
   backend: :postgres, repo: MyApp.Repo,
   table: "spectre_server_store", gam_table_prefix: "spectre_gam"
 ]]]}
```

Avvia AgentServer con `stack_runtime: MyApp.AIRuntime`, identità stabile e `gam: [storage: :ledger]`. Installa **tabelle di coordinamento, storia GAM e proiezione Domain** mediante migrazioni applicative revisionate. Gli helper SQL sono `Spectre.Ledger.ServerStore.Postgres.migration_sql/1`, `Spectre.GAM.Ledger.Store.Postgres.migration_sql/1` e `Spectre.Ledger.DomainStore.migration_sql/1`; hanno risultati diversi, quindi segui il [setup PostgreSQL completo](https://github.com/elchemista/spectre_ledger/blob/main/docs/SPECTRE_0_4.md#postgresql-coordination-store-and-approval-inbox). Per proiezioni già installate usa `DomainStore.upgrade_sql/1`. L'avvio non esegue DDL.

Un Repo può servire molti agenti con namespace distinti. Dimensiona pool e worker I/O per il carico previsto; non serve un Repo o una connessione dedicata per agente.

## Cosa esce dalla RAM

Con un adapter di proiezione, il Domain conserva radici di autorità Genesis e frontiere attive. Per ogni operazione carica i record e gruppi indicizzati necessari, applica lo stesso kernel/Fold, persiste le modifiche e rilascia le righe storiche. Nonce, decisioni ed esiti precedenti restano interrogabili nel database.

Riduce la residenza della storia; non promette memoria costante per qualsiasi numero di Duty attive o dipendenze delle prove. Le viste complete possono materializzare temporaneamente tutta la storia. Per archivi usa pagine limitate. L'avvio verifica i batch canonici e ricostruisce le righe derivate: il costo cresce con la storia, non è un ripristino istantaneo da snapshot fidato. Un database lento può ritardare commit del Domain e checkpoint.

Senza adapter di proiezione, questa rimane completa in RAM. La modalità solo RAM funziona come prima. Ledger non elimina automaticamente la storia nel database e non impone quote all'inbox: la retention è una policy applicativa.

## Conserva i payload privati fuori dallo storage di governance

L'opzione principale `payload_store: {MyApp.Payloads, archive: MyApp.PrivateArchive}` sposta i nuovi payload applicativi codificati dietro riferimenti portabili:

```elixir
defmodule MyApp.Payloads do
  @behaviour Spectre.Payload.Store

  @impl true
  def put(bytes, context, opts) do
    archive = Keyword.fetch!(opts, :archive)
    archive.put(bytes, context)
  end

  @impl true
  def fetch(reference, context, opts) do
    archive = Keyword.fetch!(opts, :archive)
    archive.fetch(reference, context)
  end
end
```

L'archivio applicativo implementa `put/2` → `{:ok, riferimento_opaco}` e `fetch/2` → `{:ok, bytes_originali}`, oppure errori. Sceglie ID, chiave oggetto o altro riferimento, cifratura, retention e backup. Spectre non impone algoritmi hash o servizi di object storage. Anche il riferimento deve evitare la diffusione di dati privati.

Sono coperti argomenti delle operazioni, presentation, payload delle evidence, dettagli delle ricevute, coordinamento e checkpoint Server. Riferimenti di autorità, classi delle operazioni, decisioni, revisioni, relazioni causali ed esiti restano fatti di governance. ID applicativi e attributi dei Principal possono ancora contenere dati personali: usa identificativi applicativi. Non è un oscuramento semantico automatico e non riscrive storia inline o backup precedenti.

Un oggetto mancante è un errore. Scrittura del payload e commit del ledger non condividono una transazione distribuita: deduplicazione e pulizia degli orfani spettano all'adapter. I worker eseguono l'I/O gestito, ma l'acquisizione del checkpoint aspetta comunque il task entro il timeout. Vedi [contratto payload](https://github.com/elchemista/spectre/blob/0.4.0/docs/PAYLOAD_STORAGE.md).

## Perdita del database e recovery esplicito

Per default, un errore di verifica/storage lascia il sistema in attesa. Il proprietario Managed rimane disponibile per segnalare il guasto. Una policy opzionale può pianificare il retry:

```elixir
defmodule MyApp.StorageRecovery do
  @behaviour Spectre.GAM.Domain.Recovery.Policy

  @impl true
  def check(_verified_context, _opts), do: :ok

  @impl true
  def recover(_incident, _opts), do: {:retry, 1_000}
end
```

Configura `gam: [recovery_policy: MyApp.StorageRecovery, ...]`. `recover/2` può restituire `:wait`, `{:retry, milliseconds}` o `:memory`. Non eseguire riparazioni lunghe dentro la callback.

Il consumer autenticato può chiamare `Spectre.Server.recover_storage(server, :retry)` dopo la riparazione oppure scegliere esplicitamente `:memory`. Il fallback RAM crea un **nuovo Domain**: non riutilizza vecchio consenso o lavoro governato in outbox. Le storie divergenti non vengono riunite automaticamente. I batch canonici mancanti non si ricostruiscono da una proiezione superstite.

Gli errori dell'inbox arrivano a `handle_approval_inbox/2` e al consumer. L'applicazione può tenere una richiesta deduplicata nello stato privato volatile e riprovare con la stessa identità; non è consenso acquisito in modo persistente. Durante la callback di errore sono ammesse solo modifiche private volatili. Scegli retention e backoff invece di creare code infinite per default.

## Il reset è diverso dal recovery

`Spectre.Server.reset(server)` avvia una nuova sessione applicativa mantenendo PID e configurazione del root. Riavvia le Skill e ripete l'inizializzazione, conservando la vecchia storia persistente. `reset(server, storage: :ephemeral)` sceglie una sessione RAM nuova. Lavoro governato irrisolto può restituire `:reset_busy`; effetti già eseguiti e memoria esterna non vengono cancellati.

`recover_storage/2` conserva la sessione applicativa mentre ripara o sostituisce lo storage di governance. Usa reset quando vuoi realmente uno stato conversazionale/applicativo nuovo. Vedi [isolamento delle sessioni](https://github.com/elchemista/spectre/blob/0.4.0/docs/AGENT_SERVER.md#resetting-an-agent-session).
