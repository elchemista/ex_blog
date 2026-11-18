# Quando serve lo Stack e come aggiungere la tua libreria di fatture

Puoi partire senza Stack. Aggiungilo quando vuoi installare capacità riutilizzabili, per esempio un helper che legge una bozza dal tuo gestionale e propone di emetterla.

## Per un agente che risponde basta il Server

Nell’Agent scrivi `use Spectre.Agent, server: MyApp.SupportServer`; nel Server scrivi `use Spectre.Server`. È ciò che genera `mix spectre.gen.agent MyApp.SupportAgent --server`. Puoi dichiarare le route, usare `respond`, gestire stato e messaggi OTP senza creare un modulo vuoto. [Prova il progetto minimo](/it/docs/getting-started).

Se hai già un client Elixir di fatturazione, puoi tenerlo indipendente da Spectre. Aggiungilo alle dipendenze della tua app come al solito. Poi scegli cosa esporre:

| Ti serve | Cosa implementi |
| --- | --- |
| Usare una funzione pura da un tuo modulo | Chiamala in Elixir. Per I/O lento usa un worker o un actor; una chiamata sincrona dentro `handle_flow` occupa il Server. |
| Un’operazione governata richiamabile con `propose` | Un pacchetto con `effects/1` e un adapter con `execute_effect/3`. [Esempio minimo completo](/it/docs/handlers). |
| Un helper `invoice(ctx, ...)` per leggere o emettere | Aggiungi `tools/1`, descrivi i due percorsi e seleziona lo Stack nel Server. È il programma qui sotto. |
| Un client o pool che richiede supervisione | Avvialo nell’albero OTP dell’app oppure usa `child_specs/2` del pacchetto e supervisiona il runtime dello Stack. Un semplice modulo di funzioni non richiede un processo dedicato. |

## 1. Adatta il tuo client

Copia i quattro blocchi Elixir in `invoice_demo.exs` in un progetto con Spectre 0.4. Il primo modulo simula il client già esistente: la bozza D1 dell’account di prova ha revisione 3 e totale EUR 24,00. Sostituisci **soltanto il confine con il client** con le chiamate reali al tuo gestionale. L’esempio locale funziona anche senza un account cloud.

L’adapter traduce i contratti. `prepare/3` esegue la validazione locale; per `{:issue, draft}` il payload è la lista `[draft]`. `invoke/3` può fare la lettura nel worker; `project/2` sceglie i dati restituiti al Server. Qui il gestionale consente all’utente di leggere quella bozza. Se la lettura richiede anche approvazione, registrala come operazione governata. Solo `execute_effect/3` chiama l’emissione.

```elixir
defmodule BillingDemo.Client do
  def draft("account-7", "D1"),
    do: {:ok, %{"id" => "D1", "revision" => 3, "total_cents" => 2400, "currency" => "EUR"}}
  def draft(_, _), do: {:error, :not_found}

  def issue("account-7", %{"id" => "D1", "revision" => 3, "total_cents" => 2400, "currency" => "EUR"}) do
    IO.puts("SDK: issued D1 revision 3")
    {:ok, %{invoice_id: "demo-invoice-1"}}
  end
  def issue(_, _), do: {:error, :definitive_no_effect, :draft_unavailable}
end

defmodule BillingDemo.Adapter do
  @behaviour Spectre.Server.GAM.EffectAdapter

  def prepare(:draft, [id], _) when is_binary(id), do: {:ok, id}
  def prepare(:issue, [%{"id" => id, "revision" => rev, "total_cents" => cents,
                         "currency" => "EUR"} = draft], _)
      when is_binary(id) and is_integer(rev) and is_integer(cents) do
    {:ok, Map.take(draft, ["id", "revision", "total_cents", "currency"])}
  end
  def prepare(_, _, _), do: {:error, :invalid_invoice_request}

  def invoke(:draft, id, context),
    do: BillingDemo.Client.draft(context.service_context.identity.subject, id)

  def project(:draft, result), do: {:ok, result}

  @impl true
  def execute_effect(:issue, draft, context),
    do: BillingDemo.Client.issue(context.identity.subject, draft)
end
```

L’account proviene dall’identità autenticata dell’app. In produzione il client verifica l’accesso e usa la versione della bozza approvata al momento dell’emissione. La simulazione lo rende visibile accettando una sola versione. Proietta campi espliciti dal tipo di risposta del tuo SDK prima di restituirli; nel client di prova sono già selezionati. Se l’API va in timeout dopo l’invio e l’esito è sconosciuto, restituisci `{:error, :ambiguous, :timeout}` e verifica il risultato presso il provider.

## 2. Registra le due operazioni e installa il pacchetto

`tools/1` crea il nome dell’helper, `invoice`. Per la lettura `:draft`, `:safe` permette di ripetere una lettura interrotta e `max_bytes` limita il dato portabile. Per `:issue`, il campo `operation: :issue_invoice` punta alla chiave **omonima** in `effects/1`. Quest’ultima registra il modulo che GAM può chiamare e l’atomo locale `:issue` passato a `execute_effect/3`. `partition: [:subject]` richiede un soggetto. Le credenziali reali appartengono al client configurato dall’applicazione.

```elixir
defmodule BillingDemo.Package do
  use Spectre.Stack.Installable, id: :billing, version: "1.0.0"

  @impl true
  def tools(_) do
    %{invoice: %{contract: 1, adapter: BillingDemo.Adapter, default: nil,
                 operations: %{
                   draft: %{path: :cognitive, retry: :safe, max_bytes: 4096},
                   issue: %{path: :governed, operation: :issue_invoice, max_bytes: 4096}
                 }}}
  end

  @impl true
  def effects(_) do
    %{issue_invoice: %{contract: 1, adapter: BillingDemo.Adapter, operation: :issue,
                       side_effect: :non_idempotent, material: :arguments,
                       partition: [:subject], schema_hash: nil, config: %{}}}
  end
end

defmodule BillingDemo.Stack do
  use Spectre.Stack
  install(BillingDemo.Package)
end
```

## 3. Collega route, helper e continuazioni

`stack:` nell’Agent seleziona il pacchetto installato. `tools:` nel Server genera la funzione locale `invoice/3`. Quando l’utente digita «issue D1», la prima chiamata legge la bozza. Il tag `:loaded` torna con la risposta del client. La clausola corrispondente passa la bozza all’helper una seconda volta, questa volta con `:issue` e `on_result: :issued`. La seconda chiamata diventa una proposta GAM.

```elixir
defmodule BillingDemo.Agent do
  use Spectre.Agent, stack: BillingDemo.Stack, server: BillingDemo.Server
  router(strategies: [:regex])
  flow :billing do
    on(:issue, regex: ~r/^issue [A-Za-z0-9-]+$/)
  end
end

defmodule BillingDemo.Server do
  use Spectre.Server, tools: BillingDemo.Stack

  @impl true
  def handle_flow({:billing, :issue}, %{text: "issue " <> id}, ctx),
    do: invoice(ctx, {:draft, id}, on_result: :loaded)
  def handle_flow(key, input, ctx), do: super(key, input, ctx)

  @impl true
  def handle_result(:loaded, {:ok, draft}, ctx),
    do: invoice(ctx, {:issue, draft}, on_result: :issued)
  def handle_result(:loaded, {:error, :not_found}, ctx), do: respond(ctx, "Draft unavailable.")
  def handle_result(:issued, {:governed, %{outcome: %{status: :succeeded}}}, ctx),
    do: respond(ctx, "Invoice issued.")
  def handle_result(:issued, {:consent, :rejected}, ctx), do: respond(ctx, "Issuing declined.")
  def handle_result(tag, result, ctx), do: super(tag, result, ctx)
end
```

## 4. Prova una bozza assente, un rifiuto e una conferma

Il consumer qui sotto guida una conversazione alla volta. L’opzione `confirm: true` richiede il consenso all’emissione per tutte le route. La bozza assente produce una risposta immediata; per quella esistente vedrai importo, valuta e revisione prima della scelta.

```elixir
alias Spectre.Server

{:ok, server} = Server.start_link(
  agent: BillingDemo.Agent, consumer: self(), identity: %{subject: "account-7"},
  gam: [operations: %{issue_invoice: [confirm: true]}]
)
[id] = System.argv()
{:ok, turn} = Server.input(server, "issue " <> id)

receive do
  {Server, ^server, {:response, ^turn, text, _}} ->
    IO.puts(text)
  {Spectre.Server.GAM.Managed, _owner, {:presentation, material}} ->
    IO.puts(material["rendered_payload"])
    ref = material["presentation_ref"]
    :ok = Server.presented(server, ref)
    receive do
      {Server, ^server, {:pending, ^turn, _}} -> :ok
    after
      5_000 -> raise "No consent wait"
    end
    choice = if IO.gets("Issue this revision? [yes/no] ") == "yes\n", do: :confirm, else: :reject
    {:ok, _} = Server.decide(server, nil, ref, choice)
    receive do
      {Server, ^server, {:response, _, text, _}} -> IO.puts(text)
    after
      5_000 -> raise "No outcome"
    end
after
  5_000 -> raise "No reply or presentation"
end
GenServer.stop(server)
```

Esegui `mix run invoice_demo.exs D2` per ottenere `Draft unavailable.`. Esegui `mix run invoice_demo.exs D1` e digita `no`: vedrai `Issuing declined.`. Ripeti con `yes`: vedrai `SDK: issued D1 revision 3`, poi `Invoice issued.`.

Nell’app reale, metti il client nella tua libreria, l’adapter e l’Installable in moduli Elixir del progetto, e il consumer nella chat o LiveView. Se ti basta l’emissione con `propose(ctx, :issue_invoice, args, on_result: :issued)`, puoi omettere l’helper e il relativo `tools/1`. Mantieni `effects/1`, lo Stack installato, i controlli dell’applicazione e la policy GAM.
