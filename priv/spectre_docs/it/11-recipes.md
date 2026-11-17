# Ricette pratiche per AgentServer

Passa dal riconoscimento a strumenti asincroni, Skill montate e proposte governate usando flussi di riferimento testati.

## Un tool puro installato completo

Il programma richiede solo il core 0.4. Salvalo come `tool_recipe.exs` nell'applicazione ed esegui `mix run tool_recipe.exs`. Stampa `UPPERCASE HELLO`. Non produce effetti esterni e non richiede risorse del runtime Stack.

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

`tools/1` descrive l'helper. `prepare/3` valida l'input, `invoke/3` gira in un worker e `project/2` restituisce dati portabili limitati. Le tre funzioni sono un'API di modulo, non un behaviour Elixir aggiuntivo. `:safe` permette il replay della cognizione incompleta, non promette effetti esterni exactly-once.

## Proposte tipizzate con Kinetic

Il modulo seguente richiede `spectre_kinetic` opzionale e compatibile. Il trasporto email è intenzionalmente simulato:

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

Installalo nello Stack con `install Spectre.Kinetic, mode: :closed_moves, actions: MyApp.MailActions, modes: [send_email: :write]`. Collega un modello reale o deterministico, crea il prompt applicativo `:send` e dichiara la route `{:mail, :send}`. La continuazione del Server è:

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

All'avvio abilita `gam: [operations: %{{:kinetic, :send_email} => [confirm: true]}]` e fornisci identità/consumer autenticati. Kinetic registra il catalogo di esecuzione; GAM verifica comunque proposta concreta e consenso umano. Conserva i metadati della proposta per validare provider, catalogo e schema.

L'applicazione deve gestire proposte vuote o multiple, output malformato, rifiuto, scadenza ed esecuzione incerta. Il frammento lascia deliberatamente i casi non gestiti a `super`: non è un client email di produzione. La [guida completa Kinetic](https://github.com/elchemista/spectre_kinetic/blob/main/README.md) include avvio e requisiti dei prompt.

`planning: false` conserva l'output consolidato per il passaggio `kinetic` esplicito. In alternativa usa il planner automatico con `planning: true`; non interpretare due volte lo stesso risultato. I token parziali dello streaming non devono eseguire azioni.

## Adapter di effetti personalizzati

Implementa `Spectre.Server.GAM.EffectAdapter.execute_effect/3` per un'operazione registrata. Restituisci `{:ok, ricevuta_portabile}` solo per un successo osservato; altrimenti usa `{:error, :failed | :definitive_no_effect | :ambiguous, reason}` secondo le prove reali.

`effects/1` dell'installable congela adapter, operazione locale, semantica dell'effetto, argomenti, partizione d'identità e configurazione. L'host deve anche abilitare l'operazione in `gam.operations`. Vedi [fixture di registrazione completa](https://github.com/elchemista/spectre/blob/0.4.0/test/server/effect_boundary_test.exs) e [contratto tool/effetti](https://github.com/elchemista/spectre/blob/0.4.0/docs/STACK_TOOLS.md). Non scegliere moduli o funzioni eseguibili da argomenti prodotti dal modello.

## Monta una Skill riutilizzabile

Questo frammento richiede `MyApp.BillingServer`, ID fattura inizializzato, effetto `:refund` registrato e configurazione GAM consentita sul root:

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

Ogni Skill montata ha processo, assigns, attese e checkpoint propri. Condivide Domain e risorse Stack del root. La allowlist del mount limita le operazioni proponibili: non le autorizza indipendentemente.

Il consumer riceve `{Spectre.Server, root, {:skill, mount, event}}`. Collega i controlli di consenso al mount e alla presentation corretti. Un AgentServer root separato usato dall'approvatore esterno ha invece un Domain diverso; vedi [comunicazione tra agenti](/it/docs/agent-to-agent).

## Reimposta una sessione in sicurezza

Il consumer configurato può richiedere:

```elixir
Spectre.Server.reset(server)
Spectre.Server.reset(server, storage: :ephemeral)
```

Sono alternative, non due chiamate da eseguire in sequenza. Il reset può rifiutare lavoro governato irrisolto. Conserva il token di sessione nei risultati consegnati dall'esterno, evitando che una callback tardiva influenzi la sessione nuova. Pulisci timer e monitor applicativi in `terminate(:reset, ctx)`.

## Un flusso completo da studiare

Lo [schema applicativo outreach](https://github.com/elchemista/spectre/blob/0.4.0/docs/examples/outreach_agent.exs) combina riconoscimento URL, lettura con Lens, estrazione contatti applicativa, bozza del modello, proposte tipizzate Kinetic e consenso email. Nomina adapter da fornire e non è uno script standalone. L'[integrazione eseguibile dei nove package](https://github.com/elchemista/spectre_ecosystem/tree/main/integration/stack_tools) fornisce fixture esterne deterministiche e testa tutto il ciclo. La [demo LiveView](https://github.com/elchemista/demo_spectre) aggiunge interfaccia e query PostgreSQL reali.
