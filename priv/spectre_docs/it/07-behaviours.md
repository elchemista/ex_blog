# Behaviour e contratti di estensione

Scegli il punto di estensione adatto per conversazioni, routing, inferenza, strumenti, persistenza o un host GAM indipendente.

Per integrare un tuo SDK con un esempio da eseguire, vedi [quali funzioni implementa il pacchetto di fatturazione](/it/docs/stack-tools).

## Come leggere il catalogo

Il core 0.4 dichiara **52 behaviour pubblici**. Le tabelle elencano tutti i moduli per responsabilità e distinguono callback formalmente richieste da `@optional_callbacks`. Una macro `use` può fornire i default richiesti: `use Spectre.Server` lo fa, quindi l'applicazione ridefinisce solo i percorsi necessari. Usa `@impl true` per vere callback e `@spec` per le API basate su funzioni.

Ogni behaviour collega i tipi esatti di argomenti e risultati. Una callback opzionale può essere necessaria per un gruppo funzionale: lo Store persistente unificato richiede tutto il gruppo della storia canonica, la proiezione persistente tutte e sei le callback oppure nessuna. I gruppi incompleti vengono rifiutati all'avvio.

Parti dal Server dei [primi passi](/it/docs/getting-started), dagli esempi sotto e dallo [storage](/it/docs/storage). Per creare un agente non devi implementare tutti questi contratti.

Se devi solo rispondere a un messaggio, apri il modulo con `use Spectre.Server` generato nella tua applicazione. Trovi l’ordine degli eventi e ogni ritorno nel [riferimento delle callback](/it/docs/server-callbacks). Il catalogo sotto serve quando vuoi sostituire un componente, per esempio il modello che genera la risposta.

## Proprietario della conversazione

| Behaviour | Scopo | Callback richieste | Callback opzionali |
| --- | --- | --- | --- |
| [`Spectre.Server`](https://hexdocs.pm/spectre/0.4.0/Spectre.Server.html) | Callback conversazionali e OTP native; `use` fornisce i default. | `code_change/3`, `format_status/1`, `handle_action/2`, `handle_call/3`, `handle_cast/2`, `handle_continue/2`, `handle_flow/3`, `handle_info/2`, `handle_pending/3`, `handle_result/3`, `handle_skill/3`, `init/2`, `terminate/2` | `assigns_schema/0`, `continuation_contracts/0`, `handle_approval_inbox/2` |

## Routing e riconoscimento

| Behaviour | Scopo | Callback richieste | Callback opzionali |
| --- | --- | --- | --- |
| [`Spectre.Router.Adapter`](https://hexdocs.pm/spectre/0.4.0/Spectre.Router.Adapter.html) | Prove limitate per regole dichiarate e visibili. | `evaluate/1` | Nessuna |
| [`Spectre.Router.Plug`](https://hexdocs.pm/spectre/0.4.0/Spectre.Router.Plug.html) | Una fase della pipeline esplicita del router. | `call/2`, `init/1` | Nessuna |
| [`Spectre.Router.Arbitrator`](https://hexdocs.pm/spectre/0.4.0/Spectre.Router.Arbitrator.html) | Selezione della route o richiesta di classificazione/chiarimento. | `decide/2` | Nessuna |
| [`Spectre.Router.SemanticCache`](https://hexdocs.pm/spectre/0.4.0/Spectre.Router.SemanticCache.html) | Lookup IntentDataset personalizzato e operazioni opzionali di revisione. | `lookup/2` | `clear/2`, `delete/3`, `examples/2`, `get_example/3`, `load_snapshot/3`, `put/3`, `relabel/4`, `snapshot/2`, `update_example/4`, `verify/3` |
| [`Spectre.Classifier.Embedding`](https://hexdocs.pm/spectre/0.4.0/Spectre.Classifier.Embedding.html) | Caricamento e uso dell’encoder di training/classificazione. | `embed/2`, `load/2` | `download/2` |

## Modelli e confini del testo

| Behaviour | Scopo | Callback richieste | Callback opzionali |
| --- | --- | --- | --- |
| [`Spectre.LLM`](https://hexdocs.pm/spectre/0.4.0/Spectre.LLM.html) | Completamento del modello; piano di prompt tipizzato opzionale. | `complete/2` | `complete_plan/2` |
| [`Spectre.Inference.Selector`](https://hexdocs.pm/spectre/0.4.0/Spectre.Inference.Selector.html) | Selezione del binding di inferenza. | `select/4` | Nessuna |
| [`Spectre.Inference.StreamAdapter`](https://hexdocs.pm/spectre/0.4.0/Spectre.Inference.StreamAdapter.html) | Streaming, cancellazione e conformità del trasporto. | `cancel/2`, `capabilities/2`, `handle_transport/2`, `open/2` | `conformance_fixture/4`, `reconcile/3`, `request_transport_item/1`, `resume/3` |
| [`Spectre.Input.Plug`](https://hexdocs.pm/spectre/0.4.0/Spectre.Input.Plug.html) | Normalizzazione o metadati dell’input prima del routing. | `call/3`, `init/1` | `rehearsable?/0` |
| [`Spectre.Reply.Sanitizer`](https://hexdocs.pm/spectre/0.4.0/Spectre.Reply.Sanitizer.html) | Pulizia limitata del testo pubblico e dello streaming opzionale. | `sanitize/2` | `finish_stream/1`, `init_stream/1`, `sanitize_chunk/2` |
| [`Spectre.Server.PublicProjection`](https://hexdocs.pm/spectre/0.4.0/Spectre.Server.PublicProjection.html) | Proiezione pubblica dei flussi di pianificazione. | `finish/1`, `init/1`, `push/2` | Nessuna |

## Capacità installate ed effetti

| Behaviour | Scopo | Callback richieste | Callback opzionali |
| --- | --- | --- | --- |
| [`Spectre.Stack.Installable`](https://hexdocs.pm/spectre/0.4.0/Spectre.Stack.Installable.html) | Compilazione di descrittori, tool, effetti e risorse immutabili. | `manifest/0` | `child_specs/2`, `compile/3`, `effects/1`, `tools/1` |
| [`Spectre.Extension`](https://hexdocs.pm/spectre/0.4.0/Spectre.Extension.html) | Contributi aggiuntivi alla compilazione dell’Agent. | Nessuna | `action_planner/1`, `action_providers/1`, `agent_config/1`, `api_version/0`, `compile/2`, `effect_executors/1`, `expand_handler/3`, `flow_constraints/2`, `id/0`, `inference_selector/1`, `setup/2` |
| [`Spectre.Server.GAM.EffectAdapter`](https://hexdocs.pm/spectre/0.4.0/Spectre.Server.GAM.EffectAdapter.html) | Esecuzione dell’operazione registrata e ammessa. | `execute_effect/3` | `effect_schema/2` |
| [`Spectre.Stack.PackageData`](https://hexdocs.pm/spectre/0.4.0/Spectre.Stack.PackageData.html) | Integrazione compatibile di cancellazione dati dei package Instance. | `erase_instance/2`, `erasure_plan/2` | Nessuna |

## Storage e recovery

| Behaviour | Scopo | Callback richieste | Callback opzionali |
| --- | --- | --- | --- |
| [`Spectre.Server.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.Server.Store.html) | Coordinamento unificato con gruppi opzionali per storia e proiezione. | `compare_and_swap/4`, `delete/3`, `fetch/2`, `put_new/3` | `gam_domain/1`, `gam_ledger/1`, `ledger_append/6`, `ledger_export/3`, `ledger_head/3`, `ledger_load/3`, `ledger_load_from/4`, `ledger_lookup_batch/4`, `ledger_read_batch/4`, `list/3`, `projection_commit/6`, `projection_fetch/5`, `projection_head/3`, `projection_open/3`, `projection_page/5`, `projection_select/6` |
| [`Spectre.Payload.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.Payload.Store.html) | Riferimenti opachi a contenuti gestiti dall’applicazione. | `fetch/3`, `put/3` | Nessuna |
| [`Spectre.GAM.Domain.Recovery.Policy`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Domain.Recovery.Policy.html) | Controlli dell’avvio verificato e policy esplicita sui guasti. | `check/2` | `failed/2`, `recover/2` |

## Approvazione e consegna dei risultati

| Behaviour | Scopo | Callback richieste | Callback opzionali |
| --- | --- | --- | --- |
| [`Spectre.Server.GAM.Managed.Approval`](https://hexdocs.pm/spectre/0.4.0/Spectre.Server.GAM.Managed.Approval.html) | Trasporto dei messaggi portabili di approvazione. | `send_message/2` | Nessuna |
| [`Spectre.Server.OutcomeDispatcher.Adapter`](https://hexdocs.pm/spectre/0.4.0/Spectre.Server.OutcomeDispatcher.Adapter.html) | Recupero di risultati esatti registrati e consegna deduplicata. | `deliver/4`, `recover/3` | Nessuna |

## Host GAM indipendenti avanzati

AgentServer configura automaticamente queste porte. Implementale per costruire un host GAM indipendente; non sono callback alternative per avviare Server.

| Behaviour | Scopo | Callback richieste | Callback opzionali |
| --- | --- | --- | --- |
| [`Spectre.GAM.Ingress`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Ingress.html) | Autenticazione delle submission e osservazione di prove ammissibili. | `authenticate/5`, `observe/4`, `ref/0` | Nessuna |
| [`Spectre.GAM.Mind`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Mind.html) | Deliberazione di candidate che restano proposte da autorizzare. | `deliberate/2`, `ref/0` | `deliberate/3` |
| [`Spectre.GAM.Attempt.Executor`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Attempt.Executor.html) | Uso di capacità temporanee per un tentativo registrato. | `contract_ref/0`, `execute/4`, `executor_ref/0` | Nessuna |
| [`Spectre.GAM.Attempt.Observer`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Attempt.Observer.html) | Osservazione indipendente tardiva senza capacità di esecuzione. | `observe/4` | Nessuna |
| [`Spectre.GAM.Secret.Broker`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Secret.Broker.html) | Rilascio di capacità temporanee secondo il profilo dichiarato. | `checkout/4`, `profile/0`, `ref/0` | Nessuna |
| [`Spectre.GAM.Genesis.Verifier`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Genesis.Verifier.html) | Verifica della radice di autorità prima dell’avvio. | `verify/2` | Nessuna |
| [`Spectre.GAM.Definition.Verifier`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Definition.Verifier.html) | Verifica statica di definizione/superficie, non ammissione. | `verify/2` | Nessuna |
| [`Spectre.GAM.Payload.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Payload.Store.html) | Verifica payload standalone, distinta da put/fetch applicativi. | `verify/2` | Nessuna |
| [`Spectre.GAM.Clock`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Clock.html) | Tempo governato delle decisioni. | `now/0` | Nessuna |
| [`Spectre.GAM.Id.Source`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Id.Source.html) | Generazione di identificativi UUIDv7 validi. | `generate/0` | Nessuna |
| [`Spectre.GAM.Ledger.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Ledger.Store.html) | Batch atomici di storia canonica e letture indicizzate. | `append/5`, `export/2`, `load/2`, `lookup_batch/3` | `head/2`, `load_from/3`, `read_batch/3` |
| [`Spectre.GAM.Domain.Projection.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Domain.Projection.Store.html) | Righe di proiezione ricostruibili e protette dalla generazione. | `commit/5`, `fetch/4`, `head/2`, `open/2`, `page/4`, `select/5` | Nessuna |

## Contratti compatibili Instance, Run ed evoluzione

Questi contratti pubblici servono integrazioni esistenti Instance/Run, Work/Vigil ed evoluzione delle definizioni. Non convertono checkpoint precedenti e non implicano il ciclo di vita del nuovo Server.

| Behaviour | Scopo | Callback richieste | Callback opzionali |
| --- | --- | --- | --- |
| [`Spectre.Action.Provider`](https://hexdocs.pm/spectre/0.4.0/Spectre.Action.Provider.html) | Catalogo di azioni tipizzate ed esecutore compatibile. | `execute/3` | `actions/1`, `schema_hash/2` |
| [`Spectre.Action.Planner`](https://hexdocs.pm/spectre/0.4.0/Spectre.Action.Planner.html) | Interpretazione di una risposta consolidata in proposte. | `plan_response/3` | `clean_reply/3`, `incremental_cleaner?/0`, `plan/3` |
| [`Spectre.Effect.Executor`](https://hexdocs.pm/spectre/0.4.0/Spectre.Effect.Executor.html) | Esecutore compatibile per effetti non action. | `execute/3` | Nessuna |
| [`Spectre.Operation.Controller`](https://hexdocs.pm/spectre/0.4.0/Spectre.Operation.Controller.html) | Reducer operativi persistenti Work/Vigil. | `__spectre_loop_definition__/0`, `apply_result/4`, `complete/2`, `init/2`, `next/2` | `apply_update/4`, `budget_exhausted/3`, `checkpoint_compatible?/2`, `handle_trigger/3` |
| [`Spectre.Turn.Handler`](https://hexdocs.pm/spectre/0.4.0/Spectre.Turn.Handler.html) | Gestione temporanea di un turn del runtime precedente. | `handle_turn/2` | Nessuna |
| [`Spectre.Turn.Dispatcher`](https://hexdocs.pm/spectre/0.4.0/Spectre.Turn.Dispatcher.html) | Consegna dei risultati Turn attraverso la policy dell’host. | `deliver_reply/3` | `action_result/3`, `execute?/3`, `fallback_reply/2`, `no_response/2`, `policy_request/3`, `satisfied_resolution/2`, `suppressed/3` |
| [`Spectre.State.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.State.Store.html) | Persistenza dello stato Agent precedente con CAS. | Nessuna | `compare_and_swap/5`, `load/3` |
| [`Spectre.Instance.CheckpointStore`](https://hexdocs.pm/spectre/0.4.0/Spectre.Instance.CheckpointStore.html) | Checkpoint, migrazione e cancellazione dell’Instance precedente. | Nessuna | `compare_and_swap/5`, `erase/3`, `erasure_status/2`, `load/2`, `migrate_instance_key/5` |
| [`Spectre.Instance.Owner`](https://hexdocs.pm/spectre/0.4.0/Spectre.Instance.Owner.html) | Acquisizione e verifica della proprietà dell’Instance precedente. | `claim/2`, `validate/3` | `claim_maintenance/3`, `release/3` |
| [`Spectre.Journal.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.Journal.Store.html) | Append al journal precedente e cancellazione opzionale. | `append/2` | `erase_instance/2` |
| [`Spectre.Receipt.Sink`](https://hexdocs.pm/spectre/0.4.0/Spectre.Receipt.Sink.html) | Acquisizione, lookup e payload opzionali delle ricevute precedenti. | `append/2`, `lookup/2` | `delete_payload/2`, `get_payload/2`, `put_payload/2` |
| [`Spectre.Event.SchemaRegistry`](https://hexdocs.pm/spectre/0.4.0/Spectre.Event.SchemaRegistry.html) | Verifica della compatibilità degli eventi globali. | `compatible?/3` | Nessuna |
| [`Spectre.Determinism.Source`](https://hexdocs.pm/spectre/0.4.0/Spectre.Determinism.Source.html) | Campioni espliciti di tempo e casualità ai confini del replay. | `monotonic_time/2`, `random_bytes/2`, `system_time/2` | Nessuna |
| [`Spectre.Definition.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.Definition.Store.html) | Pubblicazione e risoluzione di definizioni immutabili. | `durability/1`, `get/2`, `identity/1`, `put/3` | Nessuna |
| [`Spectre.Experience.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.Experience.Store.html) | Persistenza di esperienze portabili per la riflessione. | `delete/2`, `durability/1`, `get/2`, `identity/1`, `list/1`, `put/3` | Nessuna |
| [`Spectre.Projection`](https://hexdocs.pm/spectre/0.4.0/Spectre.Projection.html) | Proiezioni canoniche delle definizioni, distinte dallo storage Domain. | `id/0`, `project/2`, `version/0` | Nessuna |
| [`Spectre.Forge.Critic`](https://hexdocs.pm/spectre/0.4.0/Spectre.Forge.Critic.html) | Critico compilato su riflessione ed esperienza oscurata. | `critique/3`, `id/0`, `profile_ref/0`, `version/0` | Nessuna |
| [`Spectre.Governance.ChangeSet.Handler`](https://hexdocs.pm/spectre/0.4.0/Spectre.Governance.ChangeSet.Handler.html) | Modifiche di composizione immutabili registrate dall’host. | `apply/3`, `component_classes/0`, `operation_types/0` | Nessuna |
| [`Spectre.Governance.GC.InventoryProvider`](https://hexdocs.pm/spectre/0.4.0/Spectre.Governance.GC.InventoryProvider.html) | Inventario completo e protetto per la garbage collection di governance. | `snapshot/2` | Nessuna |

## Esempio: prove di riconoscimento con Router.Adapter

Questo adapter completo valuta solo le regole visibili nella richiesta. Configura `router strategies: [:regex, MyApp.ExactExamples]` e dichiara `exact_examples: ["...testo..."]` sulle route ammesse. Il core risolve riferimenti e scope e sceglie l'handler.

```elixir
defmodule MyApp.ExactExamples do
  use Spectre.Router.Adapter,
    id: :exact_examples, accept: 1.0, strength: :strong

  @impl true
  def evaluate(%Spectre.Router.Adapter.Request{text: text, rules: rules}) do
    matches =
      rules
      |> Enum.filter(fn rule -> text in examples(rule) end)
      |> Enum.take(32)
      |> Enum.map(&result(&1, 1.0))

    {:ok, matches}
  end
end
```

Può restituire anche `:skip`, `{:skip, reason}` o `{:error, reason}`. Fornisce prove: non può selezionare handler non dichiarati, concedere autorità o eseguire effetti.

## Esempio: modello di completamento

Questa fixture deterministica implementa il contratto senza un modello esterno:

```elixir
defmodule MyApp.FixedModel do
  @behaviour Spectre.LLM

  @impl true
  @spec complete(String.t(), keyword()) :: {:ok, String.t()}
  def complete(_prompt, _opts), do: {:ok, "A deterministic response."}
end
```

Collegala con `model MyApp.FixedModel` dentro Agent. Un adapter di produzione traduce le opzioni del provider, rispetta le scadenze e conserva gli errori deliberati. Per usarlo come classificatore, il completamento deve restituire una label di intento visibile invece di testo di risposta arbitrario.

## API di funzioni senza un behaviour

| Integrazione | Contratto di funzioni | Confine |
| --- | --- | --- |
| Embedding del router | `embed(text, opts)` → `{:ok, vettore_numerico}` o errore | Binding `embedding Module, opts`; distinto da `Classifier.Embedding` del training |
| Classificatore locale | `classify(text, opts)` → mappa della route accettata/con punteggi o errore | Binding `classifier :local, Module, opts`; non esiste un behaviour `Spectre.Classifier` |
| Servizi cognitivi Server | `generate/3` o `classify/3` | Opzione `services:`; risultati dei worker con le tuple documentate |
| Adapter tool installato | `prepare/3`, `project/2`, `invoke/3` per operazioni cognitive | `tools/1` del package nomina l'helper; preparazione pura e proiezione portabile limitata |
| Migratore checkpoint | `migrate/2` | Migrazione esplicita di proiezione/fingerprint salvati, non uno Store |
| Bridge automatico di memoria precedente | Forme supportate di `recall` e `remember`/`persist` | Verifica la governance delle scritture; preferisci tool espliciti per nuovi effetti |

Non inventare `@behaviour Spectre.Tool` o `@behaviour Spectre.Classifier`: implementa il contratto reale del descrittore o delle funzioni. Registrare un tool è distinto da adapter dell'effetto e operazione consentita. Le [ricette](/it/docs/recipes) includono un tool puro completo e un flusso con effetti. Lo [storage](/it/docs/storage) mostra moduli payload/recovery e configurazione del provider unificato.

## Verifica un'estensione

Testa input malformati, errori deliberati, timeout, riavvio/replay e isolamento. Usa `Spectre.Stack.Conformance` per gli installable e le [fixture del catalogo ufficiale](https://github.com/elchemista/spectre/blob/0.4.0/docs/BEHAVIOURS.md) per esempi completi. Gli adapter GAM standalone devono preservare identità, capacità, prove e letture al cursore esatto; le macro helper non autenticano i chiamanti.
