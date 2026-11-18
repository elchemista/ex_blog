# Build your first AgentServer

Install Spectre, generate an Agent and Server, and receive your first asynchronous response without a model or database.

## Install and generate

In an Elixir application, add this dependency to `mix.exs`:

```elixir
{:spectre, "~> 0.4.0"}
```

Then run:

```sh
mix deps.get
mix spectre.gen.agent MyApp.SupportAgent --server
mix test test/my_app/support_agent_test.exs
```

Use **`--server`** for the 0.4 architecture. The generator creates the declarative Agent, its Server callback module and a runtime test. Without that flag, it generates the retained Instance-style definition. `--dry-run` previews files; existing files require `--force` to be replaced.

Open `lib/my_app/support_agent.ex`. Its `flow :support` and `on :greeting` declarations give the route the key `{:support, :greeting}`. Open `lib/my_app/support_server.ex` and find that key in the first argument of `handle_flow/3`. Change the text passed to `respond/2` and update the assertion in the generated test. This changes the reply to “hello”.

The program below is a second standalone example. You can run it even if you skipped the generator.

## A complete model-free program

Save this as `quickstart.exs` and run `mix run quickstart.exs`. This example needs just the Agent and Server. Regex, character similarity and Jaro matching require no external service.

```elixir
defmodule Quickstart.SupportAgent do
  use Spectre.Agent, server: Quickstart.SupportServer

  router(strategies: [:regex, :bag, :jaro])

  flow :support do
    on(:pricing,
      regex: ~r/\b(price|pricing|cost)\b/i,
      bag: ["subscription plans"],
      jaro: ["monthly subscription"]
    )
  end
end

defmodule Quickstart.SupportServer do
  use Spectre.Server

  @impl true
  def handle_flow({:support, :pricing}, _input, ctx) do
    respond(ctx, "Plans start at EUR 20 per month.")
  end

  def handle_flow(:unmatched, _input, ctx) do
    respond(ctx, "Ask me about pricing.")
  end
end

{:ok, server} = Spectre.Server.start_link(agent: Quickstart.SupportAgent, consumer: self())
{:ok, interaction} = Spectre.Server.input(server, "What is the price?")

receive do
  {Spectre.Server, ^server, {:response, ^interaction, text, _metadata}} ->
    IO.puts(text)
after
  5_000 -> raise "No response from the agent"
end

GenServer.stop(server)
```

You can omit both `stack:` and `tools:` here. Add them when installing a capability such as [your own billing client](/en/docs/stack-tools). The Agent chooses a route; the Server's `handle_flow/3` responds. The Server callback module runs inside `Spectre.Server.Runtime`; it does not create a second application GenServer.

`input/3` acknowledges the interaction. The text arrives separately at the configured consumer. Do not expect `{:ok, "the answer"}` from `input/3`, or block the consumer while waiting on another synchronous call to itself.

For ordinary input matching this route, the complete path is `"What is the price?" → {:support, :pricing} → handle_flow/3 → respond/2 → {:response, interaction, text, metadata}`. A literal reply ends the path. To do more after asynchronous work, [try a continuation](/en/docs/handlers).

## Supervise a conversation

For dynamically owned conversations use the application's authenticated subject:

```elixir
{:ok, server} = Spectre.summon(
  agent: Quickstart.SupportAgent,
  subject: "customer-42",
  identity: %{subject: "customer-42"},
  consumer: self()
)
```

The application authenticates the user before supplying `subject` or `identity`. A guessed subject string is not a credential. Stable identities matter when a durable backend resumes conversations. For fixed children and complete application supervision examples, see [installation](https://github.com/elchemista/spectre/blob/0.4.0/docs/INSTALLATION.md#otp-supervision).

## Store application state in the Context

Conversation callbacks return an updated Context. Native OTP callbacks return ordinary tuples with that Context as state:

```elixir
# Clauses inside a module using Spectre.Server.
@impl true
def init(_arg, ctx), do: {:ok, assign(ctx, :requests, 0)}

@impl true
def handle_info({:set_customer, id}, ctx),
  do: {:noreply, assign(ctx, :customer_id, id)}
```

Keep portable application data in `ctx.assigns`. Use `ctx.private` for process-local handles, monitors and timers; private state is not checkpointed. Initialize restored assigns carefully rather than replacing recovered values on every startup.

## Add capabilities one at a time

Add semantic recognition or model classification through [routing](/en/docs/routing). Install tools in a Stack and handle their asynchronous results through [recipes](/en/docs/recipes). Add approval only after registering the exact effect and permitting its operation in GAM. Use [storage](/en/docs/storage) when state must survive restarts.

The [official quickstart source](https://github.com/elchemista/spectre/blob/main/docs/examples/agent_server_quickstart.exs) is executable from the core checkout. The [demo](https://github.com/elchemista/demo_spectre) adds a LiveView interface, mounted Skills and PostgreSQL; it is a larger application, not a dependency of this first program.
