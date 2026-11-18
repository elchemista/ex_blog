# Dall’input al risultato, un invio passo per passo

Scrivi un agente che risponde a «help» e, quando digiti «send», chiede il permesso di simulare un invio. Prova sia la conferma sia il rifiuto.

## 1. Crea il file della prova

In un progetto Mix con la dipendenza `{:spectre, "~> 0.4.0"}`, esegui `mix deps.get`. Crea `mail_demo.exs` nella radice del progetto e copia **i quattro blocchi Elixir di questa pagina, in ordine**, nello stesso file. Servono soltanto il core e il terminale. In un’applicazione metteresti ogni modulo nel proprio file sotto `lib/`.

Il primo blocco registra ciò che l’applicazione sa fare. Il nome pubblico è `:send_email`. Se GAM autorizza l’operazione, il runtime chiama `MailDemo.Effect.execute_effect(:deliver, args, context)`. Qui l’effetto stampa una riga nel terminale e restituisce una ricevuta simulata. Puoi così osservare esattamente quando viene eseguito.

```elixir
defmodule MailDemo.Effect do
  @behaviour Spectre.Server.GAM.EffectAdapter

  @impl true
  def execute_effect(:deliver, %{"body" => body}, _context) do
    IO.puts("EFFECT: " <> body)
    {:ok, %{simulated: true}}
  end
end

defmodule MailDemo.Package do
  use Spectre.Stack.Installable, id: :mail_demo, version: "1.0.0"

  def effects(_) do
    %{send_email: %{contract: 1, adapter: MailDemo.Effect, operation: :deliver,
                    side_effect: :non_idempotent, material: :arguments,
                    partition: [], schema_hash: nil, config: %{}}}
  end
end

defmodule MailDemo.Stack do
  use Spectre.Stack
  install(MailDemo.Package)
end
```

Nel descrittore, `adapter` e `operation` indicano modulo e clausola da chiamare. `material: :arguments` include gli argomenti nel materiale dell’approvazione. `:non_idempotent` dichiara che ripetere l’invio potrebbe duplicarlo. Questa registrazione serve a chi scrive il pacchetto o l’adapter. Se installi un pacchetto che registra già l’effetto, usi il suo nome pubblico.

## 2. Dai un nome alle due route nell’Agent

`flow :mail` raggruppa le route. Ogni `on` assegna un’etichetta a un input riconoscibile. Il router confronta il testo con i pattern e costruisce la chiave da passare al Server. Qui «send» diventa `{:mail, :send}`.

```elixir
defmodule MailDemo.Agent do
  use Spectre.Agent, stack: MailDemo.Stack, server: MailDemo.Server

  router(strategies: [:regex])

  flow :mail do
    on(:help, regex: ~r/^help$/i)
    on(:send, regex: ~r/^send$/i, protected: true)
  end
end
```

## 3. Scrivi le callback nel Server

Per «help» basta `handle_flow/3`. Spectre passa la chiave, una `%Spectre.Input{}` e il contesto di questa chiamata. `respond(ctx, testo)` accoda una risposta e restituisce il contesto aggiornato. Il turno può finire qui.

Per «send» chiediamo altro lavoro. `propose/4` accoda l’operazione `:send_email` con gli argomenti e conserva `on_result: :sent`. **Sei tu a scegliere `:sent`.** Quando arriva l’esito, Spectre mette quel tag nel primo argomento di `handle_result/3`. Nel secondo mette ciò che è successo. Elixir sceglie la prima clausola che corrisponde a entrambi.

```elixir
defmodule MailDemo.Server do
  use Spectre.Server

  @impl true
  def handle_flow({:mail, :help}, _input, ctx), do: respond(ctx, "Type send.")

  def handle_flow({:mail, :send}, _input, ctx),
    do: propose(ctx, :send_email, %{"body" => "Report ready"}, on_result: :sent)

  def handle_flow(key, input, ctx), do: super(key, input, ctx)

  @impl true
  def handle_result(:sent, {:governed, %{outcome: %{status: :succeeded}}}, ctx),
    do: respond(ctx, "Delivery completed.")

  def handle_result(:sent, {:consent, :rejected}, ctx),
    do: respond(ctx, "Delivery declined.")

  def handle_result(tag, result, ctx), do: super(tag, result, ctx)
end
```

Leggi la prima clausola così. `:sent` identifica il comando da riprendere. `{:governed, dettagli}` è il risultato di GAM. Il pattern sulla mappa richiede che `dettagli.outcome.status` sia `:succeeded` e accetta eventuali altri campi. Un rifiuto porta **lo stesso tag** e una tupla diversa. L’ultima clausola conserva il comportamento predefinito, anche per errori ed esiti incerti. Per rinominare la continuazione cambia `on_result:` e le due clausole `:sent`. La route `:send` e l’operazione `:send_email` restano valide.

## 4. Fai da utente e osserva l’esito

Questo blocco è il consumatore, ossia il processo che in un’app reale sarebbe la chat o l’interfaccia. Avvia il Server con un’identità di prova e abilita l’operazione. Prima prova la risposta semplice, poi mostra il materiale che GAM chiede di approvare. `presented/2` comunica che è stato mostrato. Dopo l’evento `:pending` la scelta della persona può essere inviata con `decide/4`. Il secondo argomento `nil` indica il Server principale.

```elixir
alias Spectre.Server

{:ok, server} = Server.start_link(
  agent: MailDemo.Agent, consumer: self(), identity: %{subject: "demo-user"},
  gam: [operations: %{send_email: [confirm: true]}]
)

{:ok, help_id} = Server.input(server, "help")
receive do
  {Server, ^server, {:response, ^help_id, text, _meta}} -> IO.puts(text)
after
  5_000 -> raise "No help response"
end

{:ok, send_id} = Server.input(server, "send")
ref = receive do
  {Spectre.Server.GAM.Managed, _owner, {:presentation, material}} ->
    IO.puts(material["rendered_payload"])
    material["presentation_ref"]
after
  5_000 -> raise "No presentation"
end
:ok = Server.presented(server, ref)

receive do
  {Server, ^server, {:pending, ^send_id, _pending_id}} -> :ok
after
  5_000 -> raise "No consent wait"
end

choice = if IO.gets("Confirm? [yes/no] ") == "yes\n", do: :confirm, else: :reject
{:ok, _decision_id} = Server.decide(server, nil, ref, choice)
receive do
  {Server, ^server, {:response, _interaction, text, _meta}} -> IO.puts(text)
after
  5_000 -> raise "No result response"
end
GenServer.stop(server)
```

Esegui `mix run mail_demo.exs`. Vedrai `Type send.`, poi la richiesta con il testo «Report ready». Rispondi `no` e vedrai `Delivery declined.`. Ripeti il comando e rispondi `yes`. Solo in questo caso compariranno prima `EFFECT: Report ready` e poi `Delivery completed.`.

## Lo schema dei due percorsi

```text
"help" → {:mail, :help} → handle_flow → respond → consumer

"send" → {:mail, :send} → handle_flow
           → propose(:send_email, ..., on_result: :sent)
           → handle_action (default) → GAM → presentazione al consumer
           → decisione umana → handle_pending (default)
             ├─ rifiuto   → handle_result(:sent, {:consent, :rejected}, ctx)
             └─ consenso → GAM verifica → execute_effect → Outcome
                           → handle_result(:sent, {:governed, dettagli}, ctx)
           → respond → consumer
```

`use Spectre.Server` fornisce le implementazioni predefinite di `init/2`, `handle_action/2` e `handle_pending/3` usate qui. L’ordine delle funzioni nel file non stabilisce l’ordine degli eventi. Per sapere quale callback scrivere per un timer, una Skill, un input già in attesa o un comando asincrono, consulta [ordine, argomenti e ritorni di tutte le callback](/it/docs/server-callbacks).
