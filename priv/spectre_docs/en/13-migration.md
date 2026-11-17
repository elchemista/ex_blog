# Migrating from 0.3 to 0.4

Migrate conversation ownership and effect execution deliberately while retaining compatible older runtime integrations where required.

Spectre 0.4 changes how new applications declare agents, own conversations and execute tools. It keeps recognition, labeled examples, training, provider adapters and Stack composition. An existing Instance application does not become an AgentServer merely by updating the dependency.

## Map the application responsibilities

| Earlier pattern | AgentServer 0.4 |
| --- | --- |
| Route DSL contains execution bodies | Agent declares routes; Server implements `handle_flow/3` |
| Instance owns Run/Turn lifecycle | Server.Runtime owns Context, workers, pending work and continuations |
| Host orchestrates `turn`/`execute` | Call `input`, return command-bearing Context, receive asynchronous results |
| `reply`, `reason`, `act` in route blocks | `respond`, `generate`, `propose` in Server callbacks |
| Policy DSL around a protected action | Registered effects, Managed GAM, `handle_action` and `handle_pending` |
| `learn: true` | `collect_intent: true` with review policy |
| Route `embedding:` examples | `semantic_examples:` |
| `via`, `:classifier`, `:semantic_cache` | `strategies`, `:local_classifier`, `:intent_dataset` |
| Instance checkpoint and Run continuation | Server checkpoint/outbox plus canonical GAM history |

Retained spellings remain aliases where documented; conflicting aliases fail. Legacy `:llm` does not enable LLM classification. Start new code with canonical strategy names.

## Migrate one workflow first

Keep the Stack; split recognition into an Agent and application behavior into a Server. Use `mix spectre.gen.agent MyApp.SupportAgent --server --dry-run` to inspect the current shape. Follow [getting started](/en/docs/getting-started), then reconnect models and tools explicitly.

Move unmatched/ambiguous handling to `handle_flow(:unmatched, input, ctx)`. Use `generate(..., on_result: tag)` and `handle_result(tag, {:generated, response}, ctx)`. A continuation tag does not declare another route. Native OTP callbacks keep their tuples, with Context as state.

Keep portable state in assigns, process-local handles in private state and long I/O in workers. Initialize restored state without replacing it. Mounted Skills now have their own Server processes and checkpoints while sharing root GAM authority.

## Reconnect consequences through GAM

Inventory operations that read protected resources, disclose data, spend resources or change the world. Register adapters and allow concrete operation names under `gam.operations`. Add `confirm: true` where needed. Move business checks to `handle_action/2` and conversation handling to `handle_pending/3`.

Installing a tool, recognizing a protected route or getting model confidence does not authorize an effect. Report observed success through `outcome.status == :succeeded`; preserve unknown results for reconciliation. If navigation requires approval, cover both Lens open and URL-based look.

Early 0.4 preview `authority: :development` selectors and manually constructed GAM host tuples are replaced by Managed GAM configuration. Current identity keys are `subject`, `conversation`, `task`, `tenant`, `org` and `organization`. Keep credentials and unrelated business attributes outside identity.

## Do not reinterpret old durable facts

There is no general Instance-checkpoint → Server-checkpoint converter. Choose an application migration boundary, preserve old records, reconcile in-flight effects and deliberately translate portable application state. An old pending “yes” cannot be invented as new GAM consent.

Server checkpoints pin application/tool compatibility fingerprints. Changes may require an explicit checkpoint migrator. Do not remove fingerprints or replay nonrepeatable effects to make recovery succeed. Database projection schema upgrades need an application migration; changing disk to Ledger is not an automatic history conversion.

A unified custom provider can implement `Spectre.Server.Store` with complete history and optional projection groups. Existing standalone storage adapters remain supported. `reset/2` initializes a new session; `recover_storage/2` preserves application state while recovering/replacing governance storage. Neither erases effects already performed or external memory.

## Verify the resulting application

Exercise deterministic and semantic recognition, separate classifier/generation models, reviewed text-only examples, vector compatibility, streamed finalization and every installed helper. Test consent rendering/rejection/expiry, duplicate delivery, restart during execution, DB outage and session-reset fencing.

Keep legacy Work/Vigil, Instance/Run or reflection integrations on their documented path until you deliberately migrate their responsibilities. Their continued public APIs do not imply that their old checkpoint formats are interchangeable with Server state.

The [full migration reference](https://github.com/elchemista/spectre/blob/0.4.0/docs/MIGRATING_TO_0_4.md) records compatibility details. Use the [ecosystem's tested dependency catalogue](/en/docs/ecosystem) and [production checks](/en/docs/testing-production) before changing a live deployment.
