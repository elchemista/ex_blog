# Behaviours and extension contracts

Choose the smallest extension point for conversations, routing, inference, tools, persistence or a standalone GAM host.

## Read this catalogue

Core 0.4 declares **52 public behaviours**. The tables group every module by responsibility and distinguish formally required callbacks from `@optional_callbacks`. A `use` macro can provide required defaults: `use Spectre.Server` does this, so an application overrides only the paths it needs. Use `@impl true` for real behaviour callbacks and `@spec` for documented function APIs.

Click a behaviour for exact argument and result types. Optional callbacks can become required as a complete feature group: a persistent unified Store needs all canonical-history callbacks, and a persisted projection implements all six callbacks or none. A partially implemented group is rejected at startup.

Start with the Server from [getting started](/en/docs/getting-started), the examples below, and [storage](/en/docs/storage). You do not need to implement all these contracts to create an agent.

## Conversation owner

| Behaviour | Purpose | Required callbacks | Optional callbacks |
| --- | --- | --- | --- |
| [`Spectre.Server`](https://hexdocs.pm/spectre/0.4.0/Spectre.Server.html) | Conversation and native OTP callbacks; `use` supplies defaults. | `code_change/3`, `format_status/1`, `handle_action/2`, `handle_call/3`, `handle_cast/2`, `handle_continue/2`, `handle_flow/3`, `handle_info/2`, `handle_pending/3`, `handle_result/3`, `handle_skill/3`, `init/2`, `terminate/2` | `assigns_schema/0`, `continuation_contracts/0`, `handle_approval_inbox/2` |

## Routing and recognition

| Behaviour | Purpose | Required callbacks | Optional callbacks |
| --- | --- | --- | --- |
| [`Spectre.Router.Adapter`](https://hexdocs.pm/spectre/0.4.0/Spectre.Router.Adapter.html) | Bounded evidence for visible declared rules. | `evaluate/1` | None |
| [`Spectre.Router.Plug`](https://hexdocs.pm/spectre/0.4.0/Spectre.Router.Plug.html) | A stage in an explicit router pipeline. | `call/2`, `init/1` | None |
| [`Spectre.Router.Arbitrator`](https://hexdocs.pm/spectre/0.4.0/Spectre.Router.Arbitrator.html) | Choose a route or request classification/clarification. | `decide/2` | None |
| [`Spectre.Router.SemanticCache`](https://hexdocs.pm/spectre/0.4.0/Spectre.Router.SemanticCache.html) | Custom IntentDataset lookup and optional review operations. | `lookup/2` | `clear/2`, `delete/3`, `examples/2`, `get_example/3`, `load_snapshot/3`, `put/3`, `relabel/4`, `snapshot/2`, `update_example/4`, `verify/3` |
| [`Spectre.Classifier.Embedding`](https://hexdocs.pm/spectre/0.4.0/Spectre.Classifier.Embedding.html) | Load and use the training/classifier encoder. | `embed/2`, `load/2` | `download/2` |

## Models and text boundaries

| Behaviour | Purpose | Required callbacks | Optional callbacks |
| --- | --- | --- | --- |
| [`Spectre.LLM`](https://hexdocs.pm/spectre/0.4.0/Spectre.LLM.html) | Model completion; optional typed prompt-plan completion. | `complete/2` | `complete_plan/2` |
| [`Spectre.Inference.Selector`](https://hexdocs.pm/spectre/0.4.0/Spectre.Inference.Selector.html) | Select an inference binding. | `select/4` | None |
| [`Spectre.Inference.StreamAdapter`](https://hexdocs.pm/spectre/0.4.0/Spectre.Inference.StreamAdapter.html) | Transport-aware streaming, cancellation and conformance. | `cancel/2`, `capabilities/2`, `handle_transport/2`, `open/2` | `conformance_fixture/4`, `reconcile/3`, `request_transport_item/1`, `resume/3` |
| [`Spectre.Input.Plug`](https://hexdocs.pm/spectre/0.4.0/Spectre.Input.Plug.html) | Normalize or annotate input before routing. | `call/3`, `init/1` | `rehearsable?/0` |
| [`Spectre.Reply.Sanitizer`](https://hexdocs.pm/spectre/0.4.0/Spectre.Reply.Sanitizer.html) | Bounded public output cleanup and optional streaming cleanup. | `sanitize/2` | `finish_stream/1`, `init_stream/1`, `sanitize_chunk/2` |
| [`Spectre.Server.PublicProjection`](https://hexdocs.pm/spectre/0.4.0/Spectre.Server.PublicProjection.html) | Project planning streams to public text. | `finish/1`, `init/1`, `push/2` | None |

## Installed capabilities and effects

| Behaviour | Purpose | Required callbacks | Optional callbacks |
| --- | --- | --- | --- |
| [`Spectre.Stack.Installable`](https://hexdocs.pm/spectre/0.4.0/Spectre.Stack.Installable.html) | Compile immutable package descriptors, tools, effects and resources. | `manifest/0` | `child_specs/2`, `compile/3`, `effects/1`, `tools/1` |
| [`Spectre.Extension`](https://hexdocs.pm/spectre/0.4.0/Spectre.Extension.html) | Additional compile-time Agent contributions. | None | `action_planner/1`, `action_providers/1`, `agent_config/1`, `api_version/0`, `compile/2`, `effect_executors/1`, `expand_handler/3`, `flow_constraints/2`, `id/0`, `inference_selector/1`, `setup/2` |
| [`Spectre.Server.GAM.EffectAdapter`](https://hexdocs.pm/spectre/0.4.0/Spectre.Server.GAM.EffectAdapter.html) | Execute only the registered admitted operation. | `execute_effect/3` | `effect_schema/2` |
| [`Spectre.Stack.PackageData`](https://hexdocs.pm/spectre/0.4.0/Spectre.Stack.PackageData.html) | Retained Instance package-data erasure integration. | `erase_instance/2`, `erasure_plan/2` | None |

## Storage and recovery

| Behaviour | Purpose | Required callbacks | Optional callbacks |
| --- | --- | --- | --- |
| [`Spectre.Server.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.Server.Store.html) | Unified coordination plus optional canonical history and projection groups. | `compare_and_swap/4`, `delete/3`, `fetch/2`, `put_new/3` | `gam_domain/1`, `gam_ledger/1`, `ledger_append/6`, `ledger_export/3`, `ledger_head/3`, `ledger_load/3`, `ledger_load_from/4`, `ledger_lookup_batch/4`, `ledger_read_batch/4`, `list/3`, `projection_commit/6`, `projection_fetch/5`, `projection_head/3`, `projection_open/3`, `projection_page/5`, `projection_select/6` |
| [`Spectre.Payload.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.Payload.Store.html) | Application-owned opaque content references. | `fetch/3`, `put/3` | None |
| [`Spectre.GAM.Domain.Recovery.Policy`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Domain.Recovery.Policy.html) | Verified startup checks and explicit outage policy. | `check/2` | `failed/2`, `recover/2` |

## Approval and result delivery

| Behaviour | Purpose | Required callbacks | Optional callbacks |
| --- | --- | --- | --- |
| [`Spectre.Server.GAM.Managed.Approval`](https://hexdocs.pm/spectre/0.4.0/Spectre.Server.GAM.Managed.Approval.html) | Transport portable approval protocol messages. | `send_message/2` | None |
| [`Spectre.Server.OutcomeDispatcher.Adapter`](https://hexdocs.pm/spectre/0.4.0/Spectre.Server.OutcomeDispatcher.Adapter.html) | Recover exact recorded results and deliver with deduplication. | `deliver/4`, `recover/3` | None |

## Advanced standalone GAM hosts

AgentServer configures these ports automatically. Implement them only when building a standalone GAM host; they are not replacement Server startup callbacks.

| Behaviour | Purpose | Required callbacks | Optional callbacks |
| --- | --- | --- | --- |
| [`Spectre.GAM.Ingress`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Ingress.html) | Authenticate submissions and observe admissible evidence. | `authenticate/5`, `observe/4`, `ref/0` | None |
| [`Spectre.GAM.Mind`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Mind.html) | Deliberate candidates; proposals remain unauthorized. | `deliberate/2`, `ref/0` | `deliberate/3` |
| [`Spectre.GAM.Attempt.Executor`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Attempt.Executor.html) | Use a short-lived capability for a committed attempt. | `contract_ref/0`, `execute/4`, `executor_ref/0` | None |
| [`Spectre.GAM.Attempt.Observer`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Attempt.Observer.html) | Independent late observation without an execution capability. | `observe/4` | None |
| [`Spectre.GAM.Secret.Broker`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Secret.Broker.html) | Issue short-lived capabilities under a declared profile. | `checkout/4`, `profile/0`, `ref/0` | None |
| [`Spectre.GAM.Genesis.Verifier`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Genesis.Verifier.html) | Verify the authority root before boot. | `verify/2` | None |
| [`Spectre.GAM.Definition.Verifier`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Definition.Verifier.html) | Static definition/surface verification, not admission. | `verify/2` | None |
| [`Spectre.GAM.Payload.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Payload.Store.html) | Standalone payload verification; distinct from application put/fetch. | `verify/2` | None |
| [`Spectre.GAM.Clock`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Clock.html) | Governed decision time. | `now/0` | None |
| [`Spectre.GAM.Id.Source`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Id.Source.html) | Generate valid UUIDv7 record identifiers. | `generate/0` | None |
| [`Spectre.GAM.Ledger.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Ledger.Store.html) | Atomic canonical history batches and indexed reads. | `append/5`, `export/2`, `load/2`, `lookup_batch/3` | `head/2`, `load_from/3`, `read_batch/3` |
| [`Spectre.GAM.Domain.Projection.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.GAM.Domain.Projection.Store.html) | Generation-fenced disposable projection rows. | `commit/5`, `fetch/4`, `head/2`, `open/2`, `page/4`, `select/5` | None |

## Retained Instance, Run and evolution contracts

These public contracts serve existing Instance/Run, Work/Vigil and definition-evolution integrations. Their availability does not convert legacy checkpoints or imply the new Server lifecycle.

| Behaviour | Purpose | Required callbacks | Optional callbacks |
| --- | --- | --- | --- |
| [`Spectre.Action.Provider`](https://hexdocs.pm/spectre/0.4.0/Spectre.Action.Provider.html) | Typed action catalog and retained execution adapter. | `execute/3` | `actions/1`, `schema_hash/2` |
| [`Spectre.Action.Planner`](https://hexdocs.pm/spectre/0.4.0/Spectre.Action.Planner.html) | Interpret a consolidated response as action proposals. | `plan_response/3` | `clean_reply/3`, `incremental_cleaner?/0`, `plan/3` |
| [`Spectre.Effect.Executor`](https://hexdocs.pm/spectre/0.4.0/Spectre.Effect.Executor.html) | Retained non-action effect executor. | `execute/3` | None |
| [`Spectre.Operation.Controller`](https://hexdocs.pm/spectre/0.4.0/Spectre.Operation.Controller.html) | Work/Vigil durable operational reducers. | `__spectre_loop_definition__/0`, `apply_result/4`, `complete/2`, `init/2`, `next/2` | `apply_update/4`, `budget_exhausted/3`, `checkpoint_compatible?/2`, `handle_trigger/3` |
| [`Spectre.Turn.Handler`](https://hexdocs.pm/spectre/0.4.0/Spectre.Turn.Handler.html) | Temporarily own a retained turn. | `handle_turn/2` | None |
| [`Spectre.Turn.Dispatcher`](https://hexdocs.pm/spectre/0.4.0/Spectre.Turn.Dispatcher.html) | Deliver retained Turn results through host policy. | `deliver_reply/3` | `action_result/3`, `execute?/3`, `fallback_reply/2`, `no_response/2`, `policy_request/3`, `satisfied_resolution/2`, `suppressed/3` |
| [`Spectre.State.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.State.Store.html) | Retained Agent state persistence and CAS. | None | `compare_and_swap/5`, `load/3` |
| [`Spectre.Instance.CheckpointStore`](https://hexdocs.pm/spectre/0.4.0/Spectre.Instance.CheckpointStore.html) | Retained Instance checkpoint, migration and erasure. | None | `compare_and_swap/5`, `erase/3`, `erasure_status/2`, `load/2`, `migrate_instance_key/5` |
| [`Spectre.Instance.Owner`](https://hexdocs.pm/spectre/0.4.0/Spectre.Instance.Owner.html) | Claim and validate retained Instance ownership. | `claim/2`, `validate/3` | `claim_maintenance/3`, `release/3` |
| [`Spectre.Journal.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.Journal.Store.html) | Retained journal append and optional erasure. | `append/2` | `erase_instance/2` |
| [`Spectre.Receipt.Sink`](https://hexdocs.pm/spectre/0.4.0/Spectre.Receipt.Sink.html) | Retained receipt acquisition, lookup and optional payloads. | `append/2`, `lookup/2` | `delete_payload/2`, `get_payload/2`, `put_payload/2` |
| [`Spectre.Event.SchemaRegistry`](https://hexdocs.pm/spectre/0.4.0/Spectre.Event.SchemaRegistry.html) | Check global event compatibility. | `compatible?/3` | None |
| [`Spectre.Determinism.Source`](https://hexdocs.pm/spectre/0.4.0/Spectre.Determinism.Source.html) | Explicit time/random samples for replay boundaries. | `monotonic_time/2`, `random_bytes/2`, `system_time/2` | None |
| [`Spectre.Definition.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.Definition.Store.html) | Immutable definition publication and resolution. | `durability/1`, `get/2`, `identity/1`, `put/3` | None |
| [`Spectre.Experience.Store`](https://hexdocs.pm/spectre/0.4.0/Spectre.Experience.Store.html) | Portable reflection experience persistence. | `delete/2`, `durability/1`, `get/2`, `identity/1`, `list/1`, `put/3` | None |
| [`Spectre.Projection`](https://hexdocs.pm/spectre/0.4.0/Spectre.Projection.html) | Canonical definition projections, not Domain storage. | `id/0`, `project/2`, `version/0` | None |
| [`Spectre.Forge.Critic`](https://hexdocs.pm/spectre/0.4.0/Spectre.Forge.Critic.html) | Compiled critic over redacted reflection/experience. | `critique/3`, `id/0`, `profile_ref/0`, `version/0` | None |
| [`Spectre.Governance.ChangeSet.Handler`](https://hexdocs.pm/spectre/0.4.0/Spectre.Governance.ChangeSet.Handler.html) | Host-registered immutable composition changes. | `apply/3`, `component_classes/0`, `operation_types/0` | None |
| [`Spectre.Governance.GC.InventoryProvider`](https://hexdocs.pm/spectre/0.4.0/Spectre.Governance.GC.InventoryProvider.html) | Fenced complete inventory for governance garbage collection. | `snapshot/2` | None |

## Example: recognition evidence with Router.Adapter

This complete adapter scores only rules visible to its request. Configure `router strategies: [:regex, MyApp.ExactExamples]` and declare `exact_examples: ["...text..."]` on eligible routes. The core resolves scoped rule references and selects the handler.

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

It can return `:skip`, `{:skip, reason}` or `{:error, reason}` instead. An adapter provides evidence; it cannot choose an undeclared handler, grant authority or execute effects.

## Example: a completion model

This deterministic fixture implements the completion contract without an external model:

```elixir
defmodule MyApp.FixedModel do
  @behaviour Spectre.LLM

  @impl true
  @spec complete(String.t(), keyword()) :: {:ok, String.t()}
  def complete(_prompt, _opts), do: {:ok, "A deterministic response."}
end
```

Bind it with `model MyApp.FixedModel` inside an Agent. A production adapter translates provider options, respects deadlines and returns deliberate provider errors. For a classifier binding, completion must return a visible intent label rather than arbitrary response text.

## Documented function APIs without a behaviour

| Integration | Function contract | Boundary |
| --- | --- | --- |
| Router embedding | `embed(text, opts)` → `{:ok, numeric_vector}` or error | Bind with `embedding Module, opts`; distinct from training `Classifier.Embedding` |
| Local classifier | `classify(text, opts)` → accepted/scored route map or error | Bind with `classifier :local, Module, opts`; there is no `Spectre.Classifier` behaviour |
| Server cognitive services | `generate/3` or `classify/3` | Startup `services:`; worker results use the documented tagged shapes |
| Installed tool adapter | `prepare/3`, `project/2`, cognitive `invoke/3` | Package `tools/1` names the helper; pure preparation and bounded portable projection |
| Checkpoint migrator | `migrate/2` | Explicit saved-projection/fingerprint migration, not a Store |
| Retained automatic memory bridge | Supported `recall` and `remember`/`persist` function forms | Audit write governance; prefer explicit installed memory tools for new effects |

Do not invent `@behaviour Spectre.Tool` or `@behaviour Spectre.Classifier`. Implement the actual descriptor/function contract. A tool's registration is separate from an effect adapter and permitted operation. [Recipes](/en/docs/recipes) contains a complete pure installed tool and an effect workflow. [Storage](/en/docs/storage) contains payload and recovery modules and unified provider configuration.

## Verify an extension

Test malformed input, deliberate errors, timeouts, restart/replay semantics and isolation. Use `Spectre.Stack.Conformance` for installables and the [official behaviour catalogue fixtures](https://github.com/elchemista/spectre/blob/0.4.0/docs/BEHAVIOURS.md) for complete contract examples. Standalone GAM adapters must preserve identity, capability, evidence and exact-cursor boundaries; helper macros do not authenticate callers for you.
