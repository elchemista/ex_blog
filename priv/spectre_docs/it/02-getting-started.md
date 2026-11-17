# Il tuo primo AgentServer

Installa Spectre, genera Agent e Server e ricevi la prima risposta asincrona senza modelli o database.

## Installa e genera

In un'applicazione Elixir, aggiungi questa dipendenza a `mix.exs`:

```elixir
{:spectre, "~> 0.4.0"}
```

Poi esegui:

```sh
mix deps.get
mix spectre.gen.agent MyApp.SupportAgent --server
mix test test/my_app/support_agent_test.exs
```

Usa **`--server`** per l'architettura della 0.4. Il generatore crea Agent dichiarativo, modulo Server e test del runtime. Senza quel flag genera la definizione precedente basata su Instance. `--dry-run` mostra i file previsti; per sostituire file esistenti serve `--force`.

## Un programma completo senza modelli

Salva questo codice in `quickstart.exs` ed esegui `mix run quickstart.exs`. Segue l'ordine **Stack → Agent → Server**. Regex, similarità dei caratteri e confronto Jaro non richiedono servizi esterni.

```elixir
defmodule Quickstart.AI do
  use Spectre.Stack
end

defmodule Quickstart.SupportAgent do
  use Spectre.Agent, stack: Quickstart.AI, server: Quickstart.SupportServer

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
  use Spectre.Server, tools: Quickstart.AI

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

Lo Stack può essere vuoto: servirà in seguito per installare strumenti e capacità dei modelli. Agent sceglie una route; `handle_flow/3` del Server risponde. Il modulo delle callback viene eseguito dentro `Spectre.Server.Runtime`: non crea un secondo GenServer applicativo.

`input/3` acquisisce l'interazione. Il testo arriva separatamente al consumer configurato. Non aspettarti `{:ok, "la risposta"}` da `input/3` e non bloccare il consumer effettuando chiamate sincrone a sé stesso.

## Supervisiona una conversazione

Per conversazioni gestite dinamicamente usa il Subject autenticato dall'applicazione:

```elixir
{:ok, server} = Spectre.summon(
  agent: Quickstart.SupportAgent,
  subject: "customer-42",
  identity: %{subject: "customer-42"},
  consumer: self()
)
```

L'applicazione autentica la persona prima di fornire `subject` o `identity`. Una stringa indovinata non è una credenziale. Le identità stabili sono necessarie per riprendere le conversazioni attraverso un backend persistente. Per figli fissi e supervisione completa consulta la [guida di installazione](https://github.com/elchemista/spectre/blob/0.4.0/docs/INSTALLATION.md#otp-supervision).

## Conserva lo stato applicativo nel Context

Le callback della conversazione restituiscono un Context aggiornato. Le callback OTP native mantengono le normali tuple, con Context come stato:

```elixir
# Clausole dentro un modulo che usa Spectre.Server.
@impl true
def init(_arg, ctx), do: {:ok, assign(ctx, :requests, 0)}

@impl true
def handle_info({:set_customer, id}, ctx),
  do: {:noreply, assign(ctx, :customer_id, id)}
```

Metti dati applicativi portabili in `ctx.assigns`. Usa `ctx.private` per riferimenti locali al processo, monitor e timer; lo stato privato non viene salvato nei checkpoint. Inizializza gli assigns senza sovrascrivere dati già recuperati a ogni avvio.

## Aggiungi una capacità alla volta

Aggiungi riconoscimento semantico o classificazione con modelli attraverso il [routing](/it/docs/routing). Installa tool nello Stack e gestisci i risultati asincroni nelle [ricette](/it/docs/recipes). Aggiungi approvazione dopo aver registrato l'effetto concreto e abilitato la sua operazione in GAM. Usa lo [storage](/it/docs/storage) quando lo stato deve sopravvivere ai riavvii.

Il [quickstart ufficiale](https://github.com/elchemista/spectre/blob/0.4.0/docs/examples/agent_server_quickstart.exs) è eseguibile dal checkout del core. La [demo](https://github.com/elchemista/demo_spectre) aggiunge LiveView, Skill montate e PostgreSQL: è un'applicazione più completa, non una dipendenza di questo programma.
