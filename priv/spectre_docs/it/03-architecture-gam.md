# Architettura e Governed Act Model

Comprendi Stack, Agent, Server e GAM prima di collegare un agente a operazioni con conseguenze.

## Tre responsabilità applicative

| Componente | Possiede | Non stabilisce |
| --- | --- | --- |
| Stack | Capacità installate, descrittori immutabili dei tool e risorse supervisionate | Il permesso di eseguire ogni tool installato |
| Agent | Flow, intenti, provider di riconoscimento e dichiarazioni delle Skill | Una conversazione attiva o il consenso umano |
| Server | Callback applicative, Context, attese e continuazioni dei risultati | Autorità soltanto perché un handler è stato selezionato |

Il runtime Server possiede il GenServer. Gli helper `generate`, `classify`, `propose` e quelli dei tool aggiungono comandi al Context restituito. Elaborazioni lente ed effetti girano in worker; i risultati tornano a una continuazione nominata. Il checkpoint rimane una barriera ordinata di persistenza: la latenza dello storage conta comunque.

Le Skill montate sono processi Server distinti con assigns, worker e checkpoint propri. Condividono il Domain GAM principale e i vincoli del mount. Due AgentServer indipendenti hanno invece normalmente due Domain indipendenti. La distinzione è importante per supervisione e approvazioni esterne.

## Cosa significa GAM

**Governed Act Model** è il modello per autorizzare lavoro con conseguenze. Il [manifesto](/it/governed-act-model) ne definisce i principi; Spectre implementa il kernel puro e fornisce Managed GAM per integrarlo in AgentServer.

Il kernel verifica autorità e fatti registrati. Managed GAM costruisce candidate, presentation ed evidence, coordina lo storage e chiama l'esecutore dopo l'ammissione. Una spiegazione convincente del modello, un punteggio del classificatore o una ricevuta del trasporto non sostituiscono l'autorità.

| Termine | Significato pratico |
| --- | --- |
| Principal | Il soggetto cui sono attribuite autorità o prove |
| Mandate e Scope | Quali operazioni sono permesse e sotto quali vincoli |
| Candidate | Operazione concreta proposta e argomenti congelati |
| Presentation | Conseguenze esatte mostrate quando serve consenso |
| Evidence | Un fatto registrato ammissibile, incluso il consenso correttamente correlato |
| Decision / admission | Se la proposta soddisfa autorità e prove richieste |
| Act e Attempt | Operazione ammessa e suo tentativo concreto di esecuzione |
| Outcome | Il risultato effettivamente osservato |
| Duty | Un obbligo registrato che può durare oltre un'attesa conversazionale |

Un Domain ordina storia e ammissione. Capacità installate e adapter di trasporto non cambiano le regole del kernel.

## Esempio: prepara un'email, poi chiedi di inviarla

Dopo aver registrato l'effetto email, il root abilita l'operazione:

```elixir
# Frammento delle opzioni di Spectre.Server.start_link/1.
identity: %{subject: "customer-42"},
consumer: chat_process,
gam: [operations: %{{:kinetic, :send_email} => [confirm: true]}]
```

Il Server propone la bozza concreta:

```elixir
# Clausole delle callback; richiedono l'effetto {:kinetic, :send_email} registrato.
def handle_flow({:mail, :send}, _input, ctx) do
  propose(ctx, {:kinetic, :send_email},
    %{"to" => ctx.assigns.recipient, "body" => ctx.assigns.draft},
    on_result: :sent)
end

def handle_result(:sent, {:governed, %{outcome: %{status: :succeeded}}}, ctx),
  do: respond(ctx, "Il servizio email ha confermato l'operazione.")

def handle_result(tag, result, ctx), do: super(tag, result, ctx)
```

Il frammento non è un client email completo: servono ActionProvider Kinetic, registrazione dell'effetto, credenziali e autorità consentita dall'applicazione. Consulta [tool e ricette](/it/docs/recipes).

## Il consenso richiede la presentazione

Il consumer autenticato mostra la Presentation esatta, ne conferma la visualizzazione e invia la scelta distinta della persona. Approvare una bozza autorizza quella bozza entro il mandato esistente; cambiare destinatario o contenuto richiede una nuova proposta appropriata. Il modello non deve chiamare le API destinate alla decisione umana.

Il consumer locale usa le API pubbliche `presented` e `decide`. L'approvazione esterna porta lo stesso requisito a un altro agente senza spostare l'autorità di esecuzione. Vedi [approvazione tra agenti](/it/docs/agent-to-agent).

## Conserva l'incertezza degli esiti

Ammissione riuscita ed esecuzione riuscita sono fatti distinti. Un servizio esterno può applicare l'effetto e poi andare in timeout. Registra l'incertezza e riconcilia con le ricevute o il meccanismo di idempotenza del servizio. Un timeout non dimostra che non sia successo nulla e non giustifica la ripetizione automatica di un effetto non ripetibile.

GAM offre un confine che l'host deve utilizzare. Se il codice applicativo chiama direttamente un client email o browser fuori da quel confine, la libreria non può governare retroattivamente l'operazione. Definisci tutta la superficie governata, inclusa la navigazione eseguita da un tool apparentemente cognitivo.

Continua con la [configurazione esatta di Managed GAM](https://github.com/elchemista/spectre/blob/0.4.0/docs/MANAGED_GAM.md), lo [storage](/it/docs/storage) e i [test](/it/docs/testing-production).
