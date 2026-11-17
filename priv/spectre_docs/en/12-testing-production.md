# Testing, profiling and production

Test observable behavior and failure boundaries, measure real process memory, and deploy with explicit storage and authority policy.

## Start with application behavior

Test the public input/response protocol before inspecting implementation details. Exercise matched, ambiguous and unmatched routes, provider failure, model generation, tool projection and every continuation your application uses. Use deterministic providers for routine regression tests, then separately test real service adapters.

For consequences assert **no execution before valid admission**, exactly the intended arguments after consent, rejection and expiry, duplicate delivery, forged/stale replies, and unknown results. Test two independently owned agents when external approval is part of the product, both with a local transport and with the deployed Pulse/HTTP adapter.

## Keep test ownership clear

Core tests run without companion libraries or a database. PostgreSQL adapter tests belong to Ledger, browser-driver tests to Lens and transport approval tests to Pulse. The ecosystem's separate integration project tests the combined Stack. Your application also needs its own real Repo/provider tests; a fake Repo does not prove SQL locking or recovery.

From a core checkout, the standard checks are:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
SPECTRE_TEST_PROJECTION=1 mix test test/gam
mix credo
mix dialyzer
mix docs --warnings-as-errors
mix run docs/examples/agent_server_quickstart.exs
mix run docs/examples/external_approval.exs
```

The release workflow covers Elixir 1.19/OTP 28 and Elixir 1.20/OTP 29. Use separate build paths for toolchains. For core's 95% combined coverage gate, generate fresh RAM and projection exports from the same source revision, then aggregate:

```sh
mix test --cover --export-coverage ram
SPECTRE_TEST_PROJECTION=1 mix test test/gam --cover --export-coverage projection
mix test.coverage
```

Do not mix older exports or include companion coverage to disguise missing core behavior. Application coverage thresholds are your policy; prioritize meaningful failure boundaries over counting lines.

## Test actual storage failure

Against an isolated disposable PostgreSQL database, test unavailable startup, stop/restart during reads and writes, ambiguous acknowledgement, owner death, namespace isolation, partial loss and restored backups. Verify that a projection cannot invent missing authority/history, previous consent cannot authorize a fresh RAM Domain, and uncertain effects are reconciled before retry.

Test reset with mounted Skills, late external replies and unresolved governed work. Distinguish an application reset from storage recovery and from subject/data erasure. Avoid running destructive test fixtures against a development or production database.

## Measure the processes that own work

A useful AgentServer memory probe samples root/Skill Servers, Domain/Sequencer, Managed gates, stores, supervised resources and transient workers. Track process memory, reductions, mailbox length, retained binaries, ETS memory, worker count, cold recovery time and idle/teardown cleanup.

For an isolated test process:

```elixir
Process.info(server, [:memory, :total_heap_size, :reductions, :message_queue_len])
```

Sample several increasing history sizes and a quiet phase; compare retained memory after work completes. Observe relevant active duties and payload sizes as well as event count. A finite flat sample supports a bound for that workload; it does not prove unlimited uptime without leaks.

`mix spectre.profile` measures retained Instance scenarios. For AgentServer and database-backed Domain residency use the [OTP profiling guide](https://github.com/elchemista/spectre/blob/0.4.0/docs/OTP_PROFILE_0_4.md) and Ledger's `bench/otp_profile.exs`, which creates an isolated cluster and reports process/row/payload measurements. Intrusive GC and call tracing belong in a dedicated VM. Measure compressed ETS and hibernation as CPU/latency tradeoffs; neither replaces retention or bounded history reads.

## Production ownership and privacy

Supervise shared Repo/model/browser resources once. Use stable names in portable configuration, live handles in private state and distinct stable identities for independent agents. Local `summon` ownership is not a distributed placement/fencing protocol; the deployment must prevent concurrent owners of the same durable namespace.

Register all consequential operations, require consent where appropriate and bind UI controls to exact mount/presentation revisions. Limit provider deadlines and stream sizes. Cancelling a local task does not prove that a remote service cancelled an already accepted operation.

Configure payload storage/encryption explicitly. Keep metric labels and logs bounded; identifiers and digests can still be personal/linkable. Database retention, backups, deletion and legal policy remain the application's responsibility. Framework records are useful evidence, not a guarantee of regulatory compliance.

## Release and operational checks

Use Doctor for compiled contracts, package diagnostics for adapter setup and real probes for service health. Review migrations, restored data, credentials and pending operations before rollout. Build docs and inspect the package before publication; publishing/tags are maintainer actions, not part of an application's runtime.

See [production](https://github.com/elchemista/spectre/blob/0.4.0/docs/PRODUCTION.md), [demo verification](https://github.com/elchemista/demo_spectre/blob/main/docs/VERIFICATION.md) and [storage](/en/docs/storage).
