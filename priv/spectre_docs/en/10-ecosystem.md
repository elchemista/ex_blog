# The optional Spectre ecosystem

Install only the capabilities your application needs and verify the exact core and satellite versions together.

## Nine independent libraries

| Library | Purpose | Server helper | Host responsibility |
| --- | --- | --- | --- |
| [spectre_beam](https://github.com/elchemista/spectre_beam) | External message channels and delivery. | `beam` | Authenticated gateway/transport configuration. |
| [spectre_directive](https://github.com/elchemista/spectre_directive) | Pure resumable mission/plan reducer. | `directive` | Application stores mission state and proposes its effects. |
| [spectre_kinetic](https://github.com/elchemista/spectre_kinetic) | Validated action proposals from consolidated model output. | `kinetic` | Typed action catalog and host executors. |
| [spectre_lab](https://github.com/elchemista/spectre_lab) | Bounded live checkpoint inspection and offline archives. | `lab` | Redaction policy; archive inspection differs from live Server state. |
| [spectre_ledger](https://github.com/elchemista/spectre_ledger) | Server coordination, canonical GAM history and historical projections. | `ledger` | File storage or application-owned PostgreSQL Repo/migrations. |
| [spectre_lens](https://github.com/elchemista/spectre_lens) | Browser navigation, page inspection and actions. | `lens` | Browser driver; govern all required navigation/action paths. |
| [spectre_mnemonic](https://github.com/elchemista/spectre_mnemonic) | Partitioned explicit memory read/search/write. | `mnemonic` | Named runtime and authenticated partition; explicit write bindings. |
| [spectre_prism](https://github.com/elchemista/spectre_prism) | Model selection for generation, classification and embeddings. | `prism` | Provider models, credentials and runtime resources. |
| [spectre_pulse](https://github.com/elchemista/spectre_pulse) | Authenticated agent messaging across transports. | `pulse` | Peer authentication and application protocol; receipts are technical. |

Core works without these packages. Dependency installation makes the module available; `install` in a Stack selects its capabilities; starting a named Stack runtime starts configured supervised resources. These are separate steps.

## Installation and source fallback

Spectre core **0.4.0 is published on Hex**:

```elixir
{:spectre, "~> 0.4.0"}
```

Companion libraries have their own versions; “Spectre 0.4 compatible” does not mean every package is version 0.4.0 or already published on Hex. Use a package's compatible published release when available. Otherwise select exact reviewed source commits from the [tested ecosystem catalogue](https://github.com/elchemista/spectre_ecosystem/blob/main/ecosystem.json) or the [demo's pinned manifest](https://github.com/elchemista/demo_spectre/blob/main/spectre.lock.exs):

```elixir
# Replace REVIEWED_SHA with the full commit from a compatible tested set.
{:spectre_lens, github: "elchemista/spectre_lens", ref: "REVIEWED_SHA"}
```

This is a dependency-template fragment, not a usable literal commit. Keep the exact source set and `mix.lock` together, including transitive companion dependencies. Do not silently combine a new core with older 0.3 package branches.

## Install capabilities in the Stack

For example, with Kinetic and Mnemonic dependencies available:

```elixir
defmodule MyApp.AI do
  use Spectre.Stack
  install Spectre.Kinetic, mode: :closed_moves, actions: MyApp.Actions
  install Spectre.Mnemonic, automatic: false, bind: [remember: :save_report] do
    isolate_by [:agent, :subject]
  end
end
```

The application supplies `MyApp.Actions`, memory configuration and the registered permitted effect for `:save_report`. This declaration does not grant authority or create an authenticated subject. Set `tools: MyApp.AI` in Server callback modules and supervise a **named** `Spectre.Stack.Runtime` when resources are required. Pass its name as `stack_runtime:`.

Generated helpers queue work and deliver portable results. Direct standalone package APIs remain useful outside AgentServer, but are not automatically durable or GAM-governed merely because the same library also supplies an installed helper.

## Read, inspect and prepare with each library

These are **Server callback fragments**, not standalone scripts. Install each named package in the selected Stack, use `tools: MyApp.AI`, declare the matching `{:tools, intent}` route in the Agent and retain error/default clauses with `super`. Only success continuations are shown. Cognitive labels do not exempt protected access or disclosure from the host's governed surface.

**Beam:** install `Spectre.Beam` with configured channels. Endpoint discovery reads capabilities; it does not deliver a message.

```elixir
def handle_flow({:tools, :channels}, _input, ctx), do: beam(ctx, {:endpoints}, on_result: :channels)
def handle_result(:channels, {:ok, endpoints}, ctx), do: assign(ctx, :endpoints, endpoints)
```

**Directive:** install `Spectre.Directive`. The pure helper returns a portable loop, including any request the application must handle; it starts no mission actor and invokes no effect.

```elixir
def handle_flow({:tools, :mission}, _input, ctx),
  do: directive(ctx, {:new, %{mission: "Review invoice", reasoner: :model}}, on_result: :mission)
def handle_result(:mission, {:directive, loop}, ctx), do: assign(ctx, :mission, loop)
```

**Kinetic:** use the typed action catalog installed above. A prior `generate(..., planning: false, on_result: :draft)` supplies the consolidated response; keep proposal metadata when subsequently calling `propose`.

```elixir
def handle_result(:draft, {:generated, response}, ctx), do: kinetic(ctx, response, on_result: :prepared)
def handle_result(:prepared, {:prepared, %{actions: actions}}, ctx), do: assign(ctx, :candidates, actions)
```

**Lab:** install `Spectre.Lab` alongside Ledger and configure a Server checkpoint. This inspects the calling runtime's trusted checkpoint, not a sibling's state or an executable replay.

```elixir
def handle_flow({:tools, :inspect}, _input, ctx), do: lab(ctx, {:inspect, :checkpoint}, on_result: :inspection)
def handle_result(:inspection, {:ok, summary}, ctx), do: assign(ctx, :inspection, summary)
```

**Ledger:** install `Spectre.Ledger` and configure its `server_store` resource or an explicit checkpoint adapter. The helper returns metadata for this Server's checkpoint; `entries` depends on backend history support.

```elixir
def handle_flow({:tools, :checkpoint}, _input, ctx), do: ledger(ctx, {:head}, on_result: :checkpoint)
def handle_result(:checkpoint, {:ok, %{revision: _} = head}, ctx), do: assign(ctx, :checkpoint, head)
```

**Lens:** install `Spectre.Lens` with a browser backend and named Stack runtime. Here `ctx.assigns.tab` is the portable reference returned by a previous open; explicitly close known tabs when finished. To require navigation consent, bind both `open` and `look`; that changes their results to governed outcomes.

```elixir
def handle_flow({:tools, :page}, _input, ctx), do: lens(ctx, {:look, ctx.assigns.tab}, on_result: :page)
def handle_result(:page, {:ok, view}, ctx), do: respond(ctx, view.title || "Page")
```

**Mnemonic:** use the isolated `automatic: false` installation above, a named Stack runtime and authenticated subject. Recall is a non-reinforcing read; no caller-supplied subject override is accepted.

```elixir
def handle_flow({:tools, :recall}, input, ctx), do: mnemonic(ctx, {:recall, input.text}, on_result: :recall)
def handle_result(:recall, {:ok, packet}, ctx), do: assign(ctx, :recall, packet)
```

**Prism:** install `Spectre.Prism` with provider/profile configuration. This chooses public profile metadata without a provider call; the next generation independently selects using its actual prompt and constraints.

```elixir
def handle_flow({:tools, :model}, _input, ctx), do: prism(ctx, %{purpose: :response_generation}, on_result: :model)
def handle_result(:model, {:selected, selection}, ctx), do: assign(ctx, :model_selection, selection)
```

**Pulse:** install `Spectre.Pulse` with its network/contact configuration. Protocol inspection is cognitive; it does not send an approval or message.

```elixir
def handle_flow({:tools, :protocol}, _input, ctx), do: pulse(ctx, {:protocol}, on_result: :protocol)
def handle_result(:protocol, {:ok, protocol}, ctx), do: assign(ctx, :protocol, protocol)
```

## Bind writes and inspect their observed outcomes

Beam delivery and Pulse sending need explicit Stack bindings, for example `install Spectre.Beam, bind: [deliver: :deliver_notice]` and `install Spectre.Pulse, bind: [send: :send_agent_message]`. Mnemonic's installation above binds `remember` to `:save_report`. Configure endpoints/peers, memory resources and corresponding `gam.operations` permissions; add `confirm: true` where required. A binding supplies no permission by itself.

These are alternative command calls inside application callbacks. The Beam `:email` endpoint and Pulse peer must exist in host configuration:

```elixir
beam(ctx, {:deliver, :email, %{to: "owner@example.com", content: %{type: :text, text: "Report ready"}}}, on_result: :sent)
mnemonic(ctx, {:remember, "The outreach report is complete."}, on_result: :sent)
pulse(ctx, {:send, %{to: "spectre://team/assistant", payload: %{type: "support.message", data: "Report ready"}}}, on_result: :sent)
```

Unlike cognitive `{:ok, value}` results, admitted writes use the governed continuation. Handle refusal, expiry and uncertainty separately; a successful Pulse transport receipt is still not human consent or a remote business outcome.

```elixir
def handle_result(:sent, {:governed, %{outcome: %{status: :succeeded}}}, ctx),
  do: respond(ctx, "The registered operation completed.")
```

## Which example should you run?

| Project | Demonstrates | External services |
| --- | --- | --- |
| [Core quickstart](https://github.com/elchemista/spectre/blob/0.4.0/docs/examples/agent_server_quickstart.exs) | Stack, router, Server, asynchronous response | None |
| [Core approval example](https://github.com/elchemista/spectre/blob/0.4.0/docs/examples/external_approval.exs) | Two independent Domains and external human approval | Mailbox transport; human/browser fixtures |
| [Nine-package integration](https://github.com/elchemista/spectre_ecosystem/tree/main/integration/stack_tools) | Real package adapters, GAM, checkpoints and recovery | Deterministic model/browser/email providers |
| [demo_spectre](https://github.com/elchemista/demo_spectre) | LiveView conversation, mounted Skills, PostgreSQL and approval UI | Read its configuration and verification guide; real provider modes are explicit |

The [ecosystem compatibility report](https://elchemista.github.io/spectre_ecosystem/) records tested revisions. Check its generation date and actual run links; a historical green report is not a guarantee about arbitrary later commits.

## Keep package boundaries clear

GAM authority belongs to core and the host's declared boundary. Pulse transports messages; Directive reduces mission state; Kinetic prepares candidates; Ledger persists facts; Lens controls its browser; Mnemonic stores memory. None can turn an unapproved operation into an approved one merely by returning a successful technical result.

Integration tests for PostgreSQL, browser drivers and authenticated messaging belong to their packages or the ecosystem, so the core remains independently usable. See [recipes](/en/docs/recipes) and [testing](/en/docs/testing-production).
