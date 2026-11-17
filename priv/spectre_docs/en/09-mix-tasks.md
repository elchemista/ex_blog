# Mix tasks and diagnostics

Use the twelve core tasks to generate, inspect, evaluate and train agents, with explicit runtime and adapter requirements.

## Generate the current architecture

```sh
mix spectre.gen.agent MyApp.SupportAgent --server --dry-run
mix spectre.gen.agent MyApp.SupportAgent --server
mix spectre.routes MyApp.SupportAgent
mix spectre.doctor --agent MyApp.SupportAgent --strict
```

`--server` selects the 0.4 Agent/Server templates. Without it, the Agent generator intentionally retains the Instance-style definition. Generators validate their plan and do not overwrite existing files without `--force`. Run the generated test before adding providers or effects.

## All twelve core tasks

| Task | Example | Purpose and requirements |
| --- | --- | --- |
| `spectre.gen.agent` | `mix spectre.gen.agent MyApp.SupportAgent --server` | Agent, Server and runtime test; `--dry-run`, `--force` |
| `spectre.gen.installable` | `mix spectre.gen.installable MyApp.TextPackage` | Stack-installable package and test; review its resource/tool contracts |
| `spectre.gen.checkpoint_store` | `mix spectre.gen.checkpoint_store MyApp.Checkpoints` | **Retained Instance.CheckpointStore** skeleton; does not generate unified Server.Store |
| `spectre.routes` | `mix spectre.routes MyApp.SupportAgent --json` | Compiled intents, nested/scoped flows and Server destinations; no handler execution |
| `spectre.doctor` | `mix spectre.doctor --agent MyApp.SupportAgent --format json` | Read-only compiled-contract diagnostics; `--strict` also rejects warnings |
| `spectre.eval` | `mix spectre.eval MyApp.SupportAgent test/fixtures/routing.jsonl` | Recognition accuracy and classifier-call policy; configured providers may run |
| `spectre.intent_dataset.export` | `mix spectre.intent_dataset.export MyApp.SupportAgent examples.jsonl` | Export verified examples; `--include-unverified`, `--source online\|all` |
| `spectre.intent_dataset.embed` | `mix spectre.intent_dataset.embed MyApp.SupportAgent examples.jsonl vectors.jsonl` | Prepare/reuse compatible vectors through configured encoder; no classifier training |
| `spectre.classifier.dataset` | `mix spectre.classifier.dataset MyApp.SupportAgent training/dataset.json --source training/raw.jsonl` | Assemble labeled training corpus; `--source` may repeat |
| `spectre.classifier.download_model` | `mix spectre.classifier.download_model --model intfloat/multilingual-e5-small` | Download/load host encoder; needs embedding dependencies and model access |
| `spectre.classifier.train` | `mix spectre.classifier.train training/dataset.json priv/intents` | Write classifier artifacts; requires appropriate encoder and labeled data |
| `spectre.profile` | `mix spectre.profile --scenario restore_runs --runs 64 --iterations 5` | Profile retained **Instance** boot/restore; not a complete AgentServer process audit |

Use `mix help <task>` for the installed version's precise options. A task being available does not provision credentials, download every dependency or construct an application Repo automatically.

## Routing evaluation in CI

With a declared `:pricing` route, save a JSONL fixture:

```json
{"id":"pricing-command","input":"What is the price?","expected_route":"pricing","expected_strategy":"regex","llm":"forbidden"}
```

Then run:

```sh
mix spectre.eval MyApp.SupportAgent test/fixtures/routing.jsonl \
  --json tmp/routing-report.json --min-pass-rate 1.0
```

Evaluation runs the configured input/router pipeline but not the selected handler, normal memory writes or effect execution. Embedding and classifier providers may incur usage. Include negatives, ambiguity and cases where LLM use is forbidden or required. Inspect both route accuracy and unnecessary model calls.

## What Doctor does and does not check

Core Doctor checks compiled declarations and contracts. It is not a live health check for a model endpoint, database, browser or email provider. Run package diagnostics and application connection/recovery probes separately. A successful Doctor report does not grant GAM authority.

## Relevant companion tasks

These commands exist only after installing the owning library. Consult its task help before use; operational tasks may touch real services.

| Package | Tasks | Notes |
| --- | --- | --- |
| Lens | `spectre.lens.doctor`, `spectre.lens.install` | Driver/browser discovery and checksum-verified installation; install may download a browser |
| Ledger | `spectre_ledger.doctor`, `spectre_ledger.gen.migration` | Backend diagnostics and archive migration generator; full Server/GAM projection setup also needs the documented separate migrations |
| Kinetic | `spectre_kinetic.extract`, `.compile`, `.show`, `.download_encoder`, `.train_classifier`, `.train_reranker` | Extract/compile action catalog, inspect artifacts, prepare optional learned recognizers; names shown after the shared `spectre_kinetic` prefix |
| Beam | `beam.status`, `beam.doctor`, `beam.chat`, `beam.send`, `beam.tail` | Gateway inspection and communication; chat/send and delivery probes can cause external work |
| Lab | `spectre_lab.doctor`, `spectre_lab.gen.test`, `spectre_lab.bundle.verify` | Read-only diagnostics, offline test skeletons and archive bundle verification |
| Mnemonic | `spectre_mnemonic.repartition` | Explicit durable record migration using an application plan; back up and review first |

Directive, Prism and Pulse do not need a Mix generator to be installed in a Stack. Keep offline deterministic tests separate from browser/model downloads, live transport delivery and database migration jobs.

See [training](/en/docs/training), [extension contracts](/en/docs/behaviours) and [profiling](/en/docs/testing-production).
