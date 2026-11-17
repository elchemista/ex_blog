# Storage, privacy and recovery

Run in RAM or configure durable coordination, canonical GAM history and database-backed projections through one provider.

## Choose a persistence mode

| Configuration under `gam:` | Behavior |
| --- | --- |
| `storage: :ephemeral` | Default RAM-only operation; no database or Ledger required |
| `storage: {:disk, path}` | Durable local authority/history; use a unique application-owned path |
| `storage: :ledger` | Discover a configured Ledger resource or explicitly selected history provider |
| `storage: {MyApp.Storage, reference}` | One custom `Spectre.Server.Store` provider for coordination and its complete history group |

Installing Ledger alone does not select a database, create tables or encrypt content. The application starts its Repo and applies migrations. Give each logical agent/session a stable distinct `identity`: Agent definition and identity select the default Domain/checkpoint namespace. A supervisor child `id:` does not partition database records.

## Three resources, one provider contract

**Coordination** stores revisioned checkpoints, inbox/outbox and command state. **Canonical GAM history** records complete append-only batches. **Projection** is a disposable, indexed read model derived from verified history.

A custom database implements `Spectre.Server.Store` and is configured once:

```elixir
{:ok, server} = Spectre.Server.start_link(
  agent: MyApp.SupportAgent,
  identity: %{tenant: "acme", subject: "customer-42", conversation: "support"},
  consumer: self(),
  gam: [storage: {MyApp.Storage, MyApp.Repo}]
)
```

`MyApp.Storage` and `MyApp.Repo` are application code, not built-in database clients. The same provider reference is the first callback argument. Spectre does not start another provider or stop a shared pool when one agent closes.

| Group | Callbacks |
| --- | --- |
| Coordination | Required `fetch/2`, `put_new/3`, `compare_and_swap/4`, `delete/3`; optional bounded `list/3` |
| Canonical history | Complete `ledger_append/6`, `ledger_load/3`, `ledger_head/3`, `ledger_read_batch/4`, `ledger_lookup_batch/4`, `ledger_export/3`; optional `ledger_load_from/4` |
| Historical projection | All six `projection_open/3`, `projection_head/3`, `projection_commit/6`, `projection_fetch/5`, `projection_page/5`, `projection_select/6`, or none |

Fetch returns `{:ok, %{revision: revision, value: value}}`, `:not_found` or error. Coordination writes acquire revisions atomically; CAS/deletion check the expected revision. History appends acquire complete batches and deduplicate batch identity. Unknown write acknowledgement stays `{:error, :ambiguous}`. Projection row changes and their cursor advance atomically, with generation fencing and exact-cursor reads. These are separate durability boundaries, not an automatic transaction across three stores.

See [the complete unified-provider fixture](https://github.com/elchemista/spectre/blob/0.4.0/test/server/unified_store_test.exs) and [callback types](/en/docs/behaviours). Existing standalone `GAM.Ledger.Store` and `Domain.Projection.Store` adapters remain compatible.

## PostgreSQL through Ledger

Install compatible Ledger, `ecto_sql` and `postgrex`, supervise your Repo, install Ledger in your Stack, then configure the Stack runtime resource:

```elixir
{Spectre.Stack.Runtime,
 stack: MyApp.AI,
 name: MyApp.AIRuntime,
 packages: [spectre_ledger: [server_store: [
   backend: :postgres, repo: MyApp.Repo,
   table: "spectre_server_store", gam_table_prefix: "spectre_gam"
 ]]]}
```

Start the AgentServer with `stack_runtime: MyApp.AIRuntime`, stable identity and `gam: [storage: :ledger]`. Install **coordination, canonical GAM and Domain projection tables** through reviewed application migrations. Their SQL helpers are `Spectre.Ledger.ServerStore.Postgres.migration_sql/1`, `Spectre.GAM.Ledger.Store.Postgres.migration_sql/1` and `Spectre.Ledger.DomainStore.migration_sql/1`; their return shapes differ, so use the [complete PostgreSQL setup](https://github.com/elchemista/spectre_ledger/blob/main/docs/SPECTRE_0_4.md#postgresql-coordination-store-and-approval-inbox). Existing projection installations use `DomainStore.upgrade_sql/1`. Runtime startup never runs DDL.

One Repo can serve many agents with distinct namespaces. Size its pool and query-worker budget for expected concurrency; do not create a Repo or connection per agent.

## What leaves RAM

With a projection adapter, the Domain retains Genesis authority roots and active frontiers. For each operation it loads the needed records and indexed dependency groups, applies the same kernel/Fold, persists changes and releases historical rows. Old nonces, decisions and outcomes remain queryable in the database.

This reduces historical residency; it does not promise constant memory for arbitrary active duties or proof closures. Full-view diagnostics can temporarily materialize history. Use bounded pages for archive queries. Cold startup verifies canonical batches and rebuilds derived rows; it is proportional to history, not an instant trusted snapshot restore. A slow database can still delay Domain commits and checkpoint barriers.

Without a projection adapter, the full projection remains in RAM. RAM-only mode works as before. Ledger does not automatically delete database history or impose an inbox quota; retention is application policy.

## Keep private payloads outside governance storage

Top-level `payload_store: {MyApp.Payloads, archive: MyApp.PrivateArchive}` externalizes new encoded application payloads behind portable references:

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

The application archive implements `put/2` → `{:ok, opaque_reference}` and `fetch/2` → `{:ok, original_bytes}`, or errors. It chooses an ID, object key or other reference, encryption, retention and backup policy. Spectre imposes no payload hash algorithm or object-storage service. References should not themselves reveal private data.

Covered boundaries include operation arguments, presentations, evidence payloads, receipt details, coordination records and Server checkpoints. Authority references, operation classes, decisions, revisions, causal links and outcomes remain governance facts. User-provided IDs and principal attributes can still contain personal data: use application identifiers. This is not an automatic semantic redactor, and old inline history/backups are not rewritten.

Missing objects are errors. A payload write and ledger commit have no shared distributed transaction; your adapter owns deduplication and orphan cleanup. Workers perform managed payload I/O, but checkpoint acquisition still waits for its bounded storage task. See [the payload contract](https://github.com/elchemista/spectre/blob/0.4.0/docs/PAYLOAD_STORAGE.md).

## Database loss and explicit recovery

Default policy waits when verification/storage fails. The Managed owner remains available to report failure. An optional policy can schedule retry:

```elixir
defmodule MyApp.StorageRecovery do
  @behaviour Spectre.GAM.Domain.Recovery.Policy

  @impl true
  def check(_verified_context, _opts), do: :ok

  @impl true
  def recover(_incident, _opts), do: {:retry, 1_000}
end
```

Configure `gam: [recovery_policy: MyApp.StorageRecovery, ...]`. `recover/2` may return `:wait`, `{:retry, milliseconds}` or `:memory`. Keep repairs outside the short policy callback.

The authenticated consumer can call `Spectre.Server.recover_storage(server, :retry)` after repair or explicitly select `:memory`. RAM fallback creates a **new Domain**: it cannot reuse old consent or governed outbox work. No divergent RAM history is automatically merged back. Missing canonical batches cannot be reconstructed from a surviving projection.

Approval inbox storage errors reach `handle_approval_inbox/2` and the consumer. An application can buffer a deduplicated request in volatile private state and retry its unchanged identity later; that buffer is not acknowledged durable consent. During the error callback, only private volatile state may change. Choose retention/backoff yourself rather than building an unbounded default queue.

## Reset is different from recovery

`Spectre.Server.reset(server)` starts a new application session while retaining the root PID and configuration. It resets mounted Skills and reruns initialization, preserving old durable audit history. `reset(server, storage: :ephemeral)` explicitly starts a fresh RAM session. Unresolved governed work can return `:reset_busy`; already executed effects and external memory are not erased.

`recover_storage/2` preserves the current application session while repairing or replacing its governance storage. Use reset only when the desired operation is a fresh conversation/application state. See [session fencing](https://github.com/elchemista/spectre/blob/0.4.0/docs/AGENT_SERVER.md#resetting-an-agent-session).
