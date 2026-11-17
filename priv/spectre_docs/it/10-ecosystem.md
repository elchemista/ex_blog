# Ecosistema opzionale Spectre

Installa solo le capacità necessarie alla tua applicazione e verifica insieme le versioni esatte di core e satelliti.

## Nove librerie indipendenti

| Libreria | Scopo | Helper Server | Responsabilità dell’host |
| --- | --- | --- | --- |
| [spectre_beam](https://github.com/elchemista/spectre_beam) | Canali esterni e consegna dei messaggi. | `beam` | Configurazione autenticata di gateway/trasporto. |
| [spectre_directive](https://github.com/elchemista/spectre_directive) | Reducer puro per missioni e piani riprendibili. | `directive` | L’applicazione salva lo stato e propone gli effetti. |
| [spectre_kinetic](https://github.com/elchemista/spectre_kinetic) | Proposte di azioni validate da output consolidato del modello. | `kinetic` | Catalogo tipizzato e esecutori applicativi. |
| [spectre_lab](https://github.com/elchemista/spectre_lab) | Ispezione live limitata dei checkpoint e archivi offline. | `lab` | Policy di oscuramento; gli archivi differiscono dallo stato live. |
| [spectre_ledger](https://github.com/elchemista/spectre_ledger) | Coordinamento Server, storia GAM e proiezioni storiche. | `ledger` | File oppure Repo PostgreSQL e migrazioni applicative. |
| [spectre_lens](https://github.com/elchemista/spectre_lens) | Navigazione, ispezione pagine e azioni browser. | `lens` | Driver browser; governa tutti i percorsi di navigazione/azione necessari. |
| [spectre_mnemonic](https://github.com/elchemista/spectre_mnemonic) | Lettura, ricerca e scrittura esplicita di memoria partizionata. | `mnemonic` | Runtime nominato e partizione autenticata; binding espliciti di scrittura. |
| [spectre_prism](https://github.com/elchemista/spectre_prism) | Selezione dei modelli per generazione, classificazione ed embedding. | `prism` | Modelli, credenziali e risorse dei provider. |
| [spectre_pulse](https://github.com/elchemista/spectre_pulse) | Messaggi autenticati tra agenti su diversi trasporti. | `pulse` | Autenticazione peer e protocollo applicativo; ricevute tecniche. |

Il core funziona senza questi package. La dipendenza rende disponibile il modulo; `install` nello Stack seleziona le capacità; il runtime Stack nominato avvia le risorse supervisionate configurate. Sono tre passaggi distinti.

## Installazione e sorgenti alternative

Il core Spectre **0.4.0 è pubblicato su Hex**:

```elixir
{:spectre, "~> 0.4.0"}
```

I satelliti hanno versioni proprie: “compatibile con Spectre 0.4” non significa che ogni package abbia versione 0.4.0 o sia già su Hex. Usa una release compatibile pubblicata quando disponibile. Altrimenti seleziona commit esatti revisionati dal [catalogo dell'ecosistema testato](https://github.com/elchemista/spectre_ecosystem/blob/main/ecosystem.json) o dal [manifest della demo](https://github.com/elchemista/demo_spectre/blob/main/spectre.lock.exs):

```elixir
# Sostituisci REVIEWED_SHA con il commit completo di un insieme verificato.
{:spectre_lens, github: "elchemista/spectre_lens", ref: "REVIEWED_SHA"}
```

È un modello di dichiarazione, non un riferimento Git utilizzabile letteralmente. Conserva insieme l'intero insieme di sorgenti e `mix.lock`, incluse le dipendenze transitive tra satelliti. Non combinare implicitamente core nuovo e branch 0.3 precedenti.

## Installa le capacità nello Stack

Per esempio, con le dipendenze Kinetic e Mnemonic disponibili:

```elixir
defmodule MyApp.AI do
  use Spectre.Stack
  install Spectre.Kinetic, mode: :closed_moves, actions: MyApp.Actions
  install Spectre.Mnemonic, automatic: false, bind: [remember: :save_report] do
    isolate_by [:agent, :subject]
  end
end
```

L'applicazione fornisce `MyApp.Actions`, configurazione della memoria ed effetto registrato/consentito per `:save_report`. La dichiarazione non concede autorità e non crea un Subject autenticato. Usa `tools: MyApp.AI` nei Server e supervisiona un `Spectre.Stack.Runtime` **nominato** quando servono risorse. Passa il nome tramite `stack_runtime:`.

Gli helper generati mettono il lavoro in coda e restituiscono risultati portabili. Le API standalone restano utili fuori da AgentServer, ma non diventano automaticamente persistenti o governate GAM solo perché la stessa libreria fornisce anche un helper installato.

## Leggere, ispezionare e preparare con ogni libreria

Sono **frammenti di callback Server**, non script autonomi. Installa il package nello Stack selezionato, usa `tools: MyApp.AI`, dichiara la route `{:tools, intent}` corrispondente in Agent e conserva errori/default con `super`. Sono mostrate solo le continuazioni positive. La classificazione cognitiva non esenta accessi protetti o divulgazioni dalla superficie governata dell'host.

**Beam:** installa `Spectre.Beam` con i canali configurati. La scoperta degli endpoint legge le capacità senza consegnare messaggi.

```elixir
def handle_flow({:tools, :channels}, _input, ctx), do: beam(ctx, {:endpoints}, on_result: :channels)
def handle_result(:channels, {:ok, endpoints}, ctx), do: assign(ctx, :endpoints, endpoints)
```

**Directive:** installa `Spectre.Directive`. L'helper puro restituisce il loop portabile e le richieste da gestire nell'applicazione; non avvia un attore missione né esegue effetti.

```elixir
def handle_flow({:tools, :mission}, _input, ctx),
  do: directive(ctx, {:new, %{mission: "Review invoice", reasoner: :model}}, on_result: :mission)
def handle_result(:mission, {:directive, loop}, ctx), do: assign(ctx, :mission, loop)
```

**Kinetic:** usa il catalogo tipizzato installato sopra. Un precedente `generate(..., planning: false, on_result: :draft)` fornisce la risposta consolidata; conserva i metadati della proposta quando successivamente chiami `propose`.

```elixir
def handle_result(:draft, {:generated, response}, ctx), do: kinetic(ctx, response, on_result: :prepared)
def handle_result(:prepared, {:prepared, %{actions: actions}}, ctx), do: assign(ctx, :candidates, actions)
```

**Lab:** installa `Spectre.Lab` insieme a Ledger e configura il checkpoint Server. Ispeziona il checkpoint fidato del runtime chiamante, non lo stato di un'altra Skill o un replay eseguibile.

```elixir
def handle_flow({:tools, :inspect}, _input, ctx), do: lab(ctx, {:inspect, :checkpoint}, on_result: :inspection)
def handle_result(:inspection, {:ok, summary}, ctx), do: assign(ctx, :inspection, summary)
```

**Ledger:** installa `Spectre.Ledger` e configura la risorsa `server_store` oppure un adapter checkpoint esplicito. L'helper restituisce metadati del checkpoint di questo Server; `entries` dipende dal supporto storico del backend.

```elixir
def handle_flow({:tools, :checkpoint}, _input, ctx), do: ledger(ctx, {:head}, on_result: :checkpoint)
def handle_result(:checkpoint, {:ok, %{revision: _} = head}, ctx), do: assign(ctx, :checkpoint, head)
```

**Lens:** installa `Spectre.Lens` con backend browser e runtime Stack nominato. `ctx.assigns.tab` è il riferimento portabile ottenuto da una precedente open; chiudi esplicitamente i tab conosciuti a fine uso. Per richiedere consenso alla navigazione collega sia `open` sia `look`: i risultati diventano esiti governati.

```elixir
def handle_flow({:tools, :page}, _input, ctx), do: lens(ctx, {:look, ctx.assigns.tab}, on_result: :page)
def handle_result(:page, {:ok, view}, ctx), do: respond(ctx, view.title || "Page")
```

**Mnemonic:** usa l'installazione isolata `automatic: false` mostrata sopra, runtime Stack nominato e Subject autenticato. Recall legge senza rinforzare la memoria; non accetta un Subject alternativo scelto dal chiamante.

```elixir
def handle_flow({:tools, :recall}, input, ctx), do: mnemonic(ctx, {:recall, input.text}, on_result: :recall)
def handle_result(:recall, {:ok, packet}, ctx), do: assign(ctx, :recall, packet)
```

**Prism:** installa `Spectre.Prism` con provider/profili. Seleziona metadati pubblici senza chiamare il provider; la generazione successiva sceglie indipendentemente usando prompt e vincoli effettivi.

```elixir
def handle_flow({:tools, :model}, _input, ctx), do: prism(ctx, %{purpose: :response_generation}, on_result: :model)
def handle_result(:model, {:selected, selection}, ctx), do: assign(ctx, :model_selection, selection)
```

**Pulse:** installa `Spectre.Pulse` con rete e contatti configurati. Ispezionare il protocollo è cognitivo: non invia richieste di consenso o messaggi.

```elixir
def handle_flow({:tools, :protocol}, _input, ctx), do: pulse(ctx, {:protocol}, on_result: :protocol)
def handle_result(:protocol, {:ok, protocol}, ctx), do: assign(ctx, :protocol, protocol)
```

## Collega le scritture e verifica gli esiti osservati

Invio Beam e Pulse richiedono binding espliciti nello Stack, per esempio `install Spectre.Beam, bind: [deliver: :deliver_notice]` e `install Spectre.Pulse, bind: [send: :send_agent_message]`. Mnemonic sopra collega `remember` a `:save_report`. Configura endpoint/peer, risorse di memoria e permessi corrispondenti in `gam.operations`; aggiungi `confirm: true` dove richiesto. Il binding da solo non concede permessi.

Queste sono chiamate alternative dentro le callback applicative. Endpoint Beam `:email` e peer Pulse devono esistere nella configurazione dell'host:

```elixir
beam(ctx, {:deliver, :email, %{to: "owner@example.com", content: %{type: :text, text: "Report ready"}}}, on_result: :sent)
mnemonic(ctx, {:remember, "The outreach report is complete."}, on_result: :sent)
pulse(ctx, {:send, %{to: "spectre://team/assistant", payload: %{type: "support.message", data: "Report ready"}}}, on_result: :sent)
```

A differenza dei risultati cognitivi `{:ok, value}`, le scritture ammesse usano la continuazione governata. Gestisci separatamente rifiuto, scadenza e incertezza; una ricevuta positiva Pulse non è consenso umano né risultato di business remoto.

```elixir
def handle_result(:sent, {:governed, %{outcome: %{status: :succeeded}}}, ctx),
  do: respond(ctx, "L'operazione registrata è stata completata.")
```

## Quale esempio eseguire?

| Progetto | Dimostra | Servizi esterni |
| --- | --- | --- |
| [Quickstart core](https://github.com/elchemista/spectre/blob/0.4.0/docs/examples/agent_server_quickstart.exs) | Stack, router, Server e risposta asincrona | Nessuno |
| [Approvazione core](https://github.com/elchemista/spectre/blob/0.4.0/docs/examples/external_approval.exs) | Due Domain indipendenti e approvazione umana esterna | Mailbox; persona/browser simulati |
| [Integrazione nove package](https://github.com/elchemista/spectre_ecosystem/tree/main/integration/stack_tools) | Adapter reali, GAM, checkpoint e recovery | Provider deterministici di modelli/browser/email |
| [demo_spectre](https://github.com/elchemista/demo_spectre) | Conversazione LiveView, Skill, PostgreSQL e UI di approvazione | Leggi configurazione e guida di verifica; modalità provider reali esplicite |

Il [report di compatibilità dell'ecosistema](https://elchemista.github.io/spectre_ecosystem/) registra le revisioni testate. Verifica data di generazione e link ai run: un risultato storico positivo non garantisce commit successivi arbitrari.

## Mantieni chiari i confini dei package

L'autorità GAM appartiene al core e alla superficie dichiarata dall'host. Pulse trasporta messaggi; Directive riduce lo stato della missione; Kinetic prepara candidate; Ledger persiste fatti; Lens controlla il browser; Mnemonic conserva memoria. Un risultato tecnico positivo non trasforma un'operazione priva di consenso in una approvata.

I test di PostgreSQL, driver browser e messaggi autenticati appartengono alle rispettive librerie o all'ecosistema, mantenendo il core utilizzabile da solo. Continua con [ricette](/it/docs/recipes) e [test](/it/docs/testing-production).
