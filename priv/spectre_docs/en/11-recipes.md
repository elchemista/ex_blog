# Practical AgentServer recipes

Move from recognition to asynchronous tools, mounted Skills and governed proposals using tested reference workflows.

## A complete pure installed tool

This program needs only core 0.4. Save it as `tool_recipe.exs` in your application and run `mix run tool_recipe.exs`. The output is `UPPERCASE HELLO`. The tool performs no external effect and needs no Stack runtime resource.

```elixir
defmodule Recipe.UppercaseTool do
  @spec prepare(:convert, term(), map()) :: {:ok, String.t()} | {:error, atom()}
  def prepare(:convert, text, _trusted) when is_binary(text), do: {:ok, text}
  def prepare(:convert, _value, _trusted), do: {:error, :text_required}

  @spec invoke(:convert, String.t(), map()) :: String.t()
  def invoke(:convert, text, _context), do: String.upcase(text)

  @spec project(:convert, String.t()) :: {:ok, String.t()}
  def project(:convert, text), do: {:ok, text}
end

defmodule Recipe.TextPackage do
  use Spectre.Stack.Installable,
    id: :text_tools, version: "0.1.0", spectre: "~> 0.4.0"

  @impl true
  def tools(_config) do
    %{
      uppercase: %{
        contract: 1, adapter: Recipe.UppercaseTool, default: :convert,
        operations: %{
          convert: %{path: :cognitive, retry: :safe, max_bytes: 65_536}
        }
      }
    }
  end
end

defmodule Recipe.TextStack do
  use Spectre.Stack
  install Recipe.TextPackage
end

defmodule Recipe.TextAgent do
  use Spectre.Agent, stack: Recipe.TextStack, server: Recipe.TextServer
  router strategies: [:regex]
  flow :text do
    on :uppercase, regex: ~r/^uppercase\b/i
  end
end

defmodule Recipe.TextServer do
  use Spectre.Server, tools: Recipe.TextStack

  @impl true
  def handle_flow({:text, :uppercase}, input, ctx),
    do: uppercase(ctx, input.text, on_result: :uppercased)

  def handle_flow(route, input, ctx), do: super(route, input, ctx)

  @impl true
  def handle_result(:uppercased, text, ctx) when is_binary(text),
    do: respond(ctx, text)

  def handle_result(tag, result, ctx), do: super(tag, result, ctx)
end

{:ok, server} = Spectre.Server.start_link(agent: Recipe.TextAgent, consumer: self())
{:ok, interaction} = Spectre.Server.input(server, "uppercase hello")
receive do
  {Spectre.Server, ^server, {:response, ^interaction, text, _metadata}} ->
    IO.puts(text)
after
  5_000 -> raise "No tool result"
end
GenServer.stop(server)
```

`tools/1` describes the helper. `prepare/3` validates input, `invoke/3` runs in a worker and `project/2` yields portable bounded data. These three functions are a module API, not a separate Elixir tool behaviour. `:safe` allows replay of unfinished cognition; it does not promise exactly-once external effects.

## Typed action proposals with Kinetic

This next module requires the optional compatible `spectre_kinetic` dependency. It is deliberately a simulated mail transport:

```elixir
defmodule MyApp.MailActions do
  use SpectreKinetic
  @al ~s(SEND EMAIL TO="dev@example.com" BODY="Hello")
  @doc "Simulate a mail operation; replace with the host transport."
  @spec send_email(String.t(), String.t()) :: {:ok, map()}
  def send_email(to, body),
    do: {:ok, %{to: to, body: body, simulated: true}}
end
```

Install it in the Stack with `install Spectre.Kinetic, mode: :closed_moves, actions: MyApp.MailActions, modes: [send_email: :write]`. Bind a real or deterministic model, create the application's `:send` prompt, and declare a `{:mail, :send}` route. The Server continuation is:

```elixir
# Server clauses; require the configured model, :send prompt and Kinetic Stack.
def handle_flow({:mail, :send}, _input, ctx),
  do: generate(ctx, :send, planning: false, on_result: :draft)

def handle_result(:draft, {:generated, response}, ctx),
  do: kinetic(ctx, response, on_result: :prepared)

def handle_result(:prepared, {:prepared, %{actions: [proposal]}}, ctx) do
  propose(ctx, proposal.operation, proposal.args,
    proposal_metadata: proposal.metadata, on_result: :sent)
end

def handle_result(:sent, {:governed, %{outcome: %{status: :succeeded}}}, ctx),
  do: respond(ctx, "The registered effect completed.")

def handle_result(tag, result, ctx), do: super(tag, result, ctx)
```

At startup enable `gam: [operations: %{{:kinetic, :send_email} => [confirm: true]}]` and supply the authenticated consumer/identity. Installing Kinetic registers its execution catalog; GAM still checks the concrete proposal and human consent. Preserve proposal metadata for provider/catalog/schema validation.

Handle empty or multiple proposals, malformed model output, refusal, expiry and unknown execution results explicitly in the application. This fragment intentionally leaves unhandled cases to `super`; it is not a production mail application. The [complete Kinetic guide](https://github.com/elchemista/spectre_kinetic/blob/main/README.md) shows startup and prompt requirements.

`planning: false` preserves consolidated model output for the explicit `kinetic` step. Alternatively use the automatic planner with `planning: true`; do not run both interpretation paths for the same result. Partial streaming tokens must never invoke actions.

## Custom effect adapters

Implement `Spectre.Server.GAM.EffectAdapter.execute_effect/3` for a registered operation. Return `{:ok, portable_receipt}` only for an observed success; otherwise use `{:error, :failed | :definitive_no_effect | :ambiguous, reason}` according to actual evidence.

An installable's `effects/1` freezes adapter, package operation, side-effect semantics, argument material, identity partition and configuration. The host also permits the operation under `gam.operations`. See the [complete registration fixture](https://github.com/elchemista/spectre/blob/0.4.0/test/server/effect_boundary_test.exs) and [tool/effect contract](https://github.com/elchemista/spectre/blob/0.4.0/docs/STACK_TOOLS.md). Never obtain a module/function to execute from model-supplied arguments.

## Mount a reusable Skill

This declaration/callback fragment requires `MyApp.BillingServer`, an initialized invoice ID, a registered `:refund` effect and permitted root GAM configuration:

```elixir
defmodule MyApp.BillingSkill do
  use Spectre.Skill, id: :billing, server: MyApp.BillingServer

  flow :billing do
    on :refund, regex: ~r/^refund$/i, protected: true
    on :status, regex: ~r/^billing status$/i
  end
end

# Inside the root Agent:
skill MyApp.BillingSkill, as: :billing, governed: [:refund]

# Inside MyApp.BillingServer, which uses Spectre.Server:
def handle_flow({:billing, :refund}, _input, ctx),
  do: propose(ctx, :refund, %{invoice_id: ctx.assigns.invoice_id}, on_result: :refunded)
```

Each mounted Skill has its own process, assigns, pending work and checkpoint. It shares the root's Domain and Stack resources. The mount allowlist restricts which operations it may propose; it does not grant those operations independently.

The consumer receives `{Spectre.Server, root, {:skill, mount, event}}`. Bind approval controls to the correct mount and presentation. A separate root AgentServer used for an external approver has a different Domain; see [agent-to-agent](/en/docs/agent-to-agent).

## Reset a session safely

The configured consumer can request:

```elixir
Spectre.Server.reset(server)
Spectre.Server.reset(server, storage: :ephemeral)
```

Treat these as alternative operations, not two calls to run in sequence. Reset can refuse unresolved governed work. Keep session tokens with externally delivered results so a late callback cannot affect the new session. Clean application-owned timers and monitors in `terminate(:reset, ctx)`.

## A workflow to study next

The [outreach application sketch](https://github.com/elchemista/spectre/blob/0.4.0/docs/examples/outreach_agent.exs) combines URL recognition, Lens page inspection, host contact extraction, model drafting, typed Kinetic proposals and email consent. It names application adapters and is not a standalone script. The [executable nine-package integration](https://github.com/elchemista/spectre_ecosystem/tree/main/integration/stack_tools) supplies deterministic external fixtures and tests the full loop. The [LiveView demo](https://github.com/elchemista/demo_spectre) adds a UI and real PostgreSQL queries.
