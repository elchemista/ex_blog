# Callback del Server, ordine e contratti

Scegli la callback in base all’evento che devi gestire. Qui trovi chi la chiama, quali dati riceve, cosa restituire e quali opzioni collegano una route al lavoro successivo.

## Dove scrivere il codice

Con `mix spectre.gen.agent MyApp.SupportAgent --server` ottieni due moduli e un test. In `lib/my_app/support_agent.ex` scrivi `flow` e `on`. In `lib/my_app/support_server.ex` scrivi le funzioni `handle_*` dentro `use Spectre.Server`. Il collegamento è `server: MyApp.SupportServer` nell’Agent. In `test/my_app/support_agent_test.exs` invia un input al processo e osserva il messaggio ricevuto dal consumer.

Per una risposta immediata basta una clausola di `handle_flow/3`. Per un risultato asincrono personalizzato aggiungi `handle_result/3`. Puoi anche avviare il lavoro in `init/2` o da un messaggio OTP. Se parti da zero, [esegui prima l’esempio mail completo](/it/docs/handlers).

## In quale ordine entrano le callback

```text
avvio → init(arg, ctx)
input → normalizzazione e pipeline di input
      ├─ interrupt globale riconosciuto → sospende l’attesa → handle_flow
      ├─ attesa in primo piano → handle_pending
      └─ altrimenti → turn handler opzionali del root
                      ├─ risposta anticipata → handle_result(:pre_route, ...)
                      └─ continua → router → handle_flow(chiave o :unmatched, ...)
contesto restituito → acquisizione dei comandi in ordine
      ├─ respond → messaggio al consumer
      ├─ generate / classify / call_actor → worker → handle_result
      └─ propose → handle_action → GAM → eventuale consenso → esito → handle_result
```

Lo schema segue un input ordinario. Una decisione associata a una presentazione punta direttamente all’attesa e alla sua revisione. Un input preparato per una Skill con route già scelta salta il secondo riconoscimento. Un errore di preparazione può arrivare direttamente a `handle_result(:input, {:error, reason}, ctx)`. I messaggi OTP possono arrivare tra questi eventi. Le clausole della **stessa** funzione invece seguono le regole di pattern matching di Elixir: metti i casi specifici prima del caso generico.

## Cosa ricevi in input e nel contesto

Con `Server.input(server, %{"text" => "send", "meta" => %{"locale" => "it"}})` il chiamante riceve `{:ok, interaction_id}` se l’input viene accettato. Nella callback ricevi una struct:

```elixir
%Spectre.Input{text: "send", meta: %{"locale" => "it"},
               raw: %{"text" => "send", "meta" => %{"locale" => "it"}}, source: nil}
```

Questo è il risultato della normalizzazione prima di eventuali trasformazioni. `text` è il testo da riconoscere, `meta` contiene i dati accessori, `raw` conserva l’input originale e `source` descrive la provenienza quando disponibile. Anche una semplice stringa è valida. L’identità autenticata proviene dall’applicazione.

`%Spectre.Server.Context{}` è la vista della callback. Leggi `ctx.identity`, `ctx.session`, `ctx.skill`, `ctx.interaction`, `ctx.input`, `ctx.routing`, `ctx.memory` e `ctx.pending` quando presenti. `get_pending(ctx, id)` trova anche le attese sospese. Salva lo stato applicativo portabile con `assign(ctx, key, value)`, e timer o monitor locali con `put_private/3`. Restituisci il contesto di **questa** chiamata: una pipe come `ctx |> assign(:seen, true) |> respond("OK")` conserva sia lo stato sia il comando.

## Tutte le callback di conversazione

| Firma | Evento, ritorno e comportamento predefinito |
| --- | --- |
| `init(arg, ctx)` | Avvio o reset. `arg` viene da `:init_arg`. Restituisci `{:ok, ctx}` (default), `{:ok, ctx, action}`, `:ignore` o `{:stop, reason}`. Inizializza gli assigns tenendo conto dei dati recuperati. |
| `handle_flow(key, input, ctx)` | Route selezionata o `:unmatched`. Restituisci il contesto. Scrivi una clausola per ogni route gestita: il default risponde a `:unmatched` e segnala errore per una route riconosciuta senza implementazione. |
| `handle_pending(pending, input, ctx)` | Nuovo input destinato a un’attesa in primo piano. Restituisci il contesto. Il default risolve `%{kind: :reply, id: id}` con `{:ok, input}`. Per `:consent` conferma, rifiuta o rispiega la presentazione. |
| `handle_action(action, ctx)` | Alla proposta governata, prima dell’ammissione. Riceve `%{operation: op, args: args, metadata: meta}`. Restituisci `:default`, `:confirm`, `{:confirm, policy_map}` o `{:reject, reason}`. Qui puoi restringere la policy per questa richiesta. |
| `handle_result(tag, result, ctx)` | Un comando termina, arriva un risultato consegnato o un errore. Restituisci il contesto. Il default risponde con il testo generato, prosegue un piano, gestisce errori ed esiti incerti, altrimenti tace. |
| `handle_skill(mount, event, ctx)` | Il Server principale riceve un evento della Skill, ad esempio `{:response, id, text, meta}`. Restituisci il contesto. Default silenzioso. Anteprime e notifiche diagnostiche hanno un percorso dedicato. |
| `handle_approval_inbox(event, ctx)` | L’inbox dell’approvatore esterno segnala ad esempio ricezione, duplicato, decisione, errore storage o tick configurato. Restituisci `:default` o il contesto aggiornato. La scelta umana entra tramite l’API di approvazione. |

## Messaggi OTP e contratti opzionali

Per i messaggi applicativi usa le callback GenServer con il contesto al posto dello stato. I messaggi dei worker e dei timer interni vengono gestiti dal runtime. Nelle tuple seguenti `action` può essere `{:continue, value}`, `:hibernate`, `:infinity` o un timeout non negativo in millisecondi.

| Firma | Quando e cosa restituire |
| --- | --- |
| `handle_call(request, from, ctx)` | Chiamata sincrona. `{:reply, reply, ctx}`, anche con un quarto elemento `action`; `{:noreply, ctx}` per rispondere più tardi con `GenServer.reply/2`. Default: risponde con errore per una richiesta sconosciuta. |
| `handle_cast(message, ctx)` | Cast asincrono. `{:noreply, ctx}` (default) o `{:noreply, ctx, action}`. |
| `handle_info(message, ctx)` | Messaggio applicativo, timer o monitor. Stessi ritorni di `handle_cast/2`. |
| `handle_continue(value, ctx)` | Esegue il lavoro richiesto da `{:continue, value}`. Stessi ritorni di `handle_cast/2`. |
| `terminate(reason, ctx)` | Chiusura o reset: libera le risorse applicative quando OTP invoca la callback. Ritorno ignorato, default `:ok`. |
| `code_change(old_vsn, ctx, extra)` | Upgrade OTP: `{:ok, ctx}` o `{:error, reason}`. Default: conserva il contesto. |
| `format_status(status)` | Ispezione OTP. Riceve la mappa di stato già filtrata, restituisce una mappa. Default: la stessa. |
| `assigns_schema()` | Schema facoltativo degli assigns. Una mappa di campi oppure `nil` (default). |
| `continuation_contracts()` | Schema facoltativo per tag e forme dei risultati. Se attivo, dichiara ogni tag esplicito di `on_result:`. Default `nil`. |

Le callback OTP di messaggistica possono anche terminare con `{:stop, reason, ctx}`; una chiamata sincrona può restituire `{:stop, reason, reply, ctx}`. Le callback di conversazione come `handle_flow/3` restituiscono invece il contesto direttamente. Quando personalizzi solo alcuni casi, termina con una clausola `super(...)` per conservare il comportamento degli altri.

## Opzioni di flow, route e Skill

| Dichiarazione | Effetto e motivo per usarla |
| --- | --- |
| `flow :mail, defaults: [...]` | Raggruppa route. I default scendono nelle route e nei flow annidati; l’opzione più specifica prevale. |
| `on :send, regex: ~r/^send$/i` | Nomina l’intento e riconosce un pattern o una lista di pattern. La chiave è `{:mail, :send}`; due flow annidati danno per esempio `{[:support, :mail], :send}`. |
| `bag:`, `jaro:`, `semantic_examples:` | Esempi testuali per similarità di stringhe (bag/Jaro) o vettoriale (embedding). Abilita la strategia nel router e configura il provider per i vettori. |
| `match_with:`, `check:`, `checks:` | Limita le strategie ammesse per la route o filtrala in base a testo e metadati. Per esempio `check: {:language, ["it"]}`. |
| `collect_intent:`, `dataset_lookup:` | Il primo abilita la raccolta degli esempi idonei per la route; il secondo permette di escluderla dalla ricerca nel dataset. Il training è un passaggio distinto. |
| `protected: true` | Segna la route nel contesto di routing. Su una proposta fatta in quel contesto Managed GAM richiede conferma. Una semplice risposta testuale continua normalmente. Ometterlo (default `false`) lascia applicabili i requisiti dell’operazione. |
| `use Spectre.Skill, id: ..., server: ...` | Con `server:` il mount ha processo e callback propri, ma condivide il Domain. Senza `server:` le route dichiarative vengono gestite dal Server principale. |
| `skill Module, as: ..., bind: ..., governed: [...]` | `as:` sceglie il nome locale (default: ID della Skill). `bind:` associa i riferimenti logici ad azioni concrete. `governed:` restringe le operazioni alla lista del mount, entro quelle abilitate nel root. |

Esempio: monta `BillingSkill` come `:invoices`. Se la Skill dichiara `flow :billing` e `on :refund`, il suo Server riceve `{:billing, :refund}` e `ctx.skill.id == :invoices`. Per un mount dichiarativo senza Server, la chiave ricevuta dal root è `{{{:skill, :invoices}, :billing}, :refund}`. Metti `confirm: true` in `gam: [operations: %{refund: [confirm: true]}]` se vuoi conferma sull’operazione anche quando viene proposta da altre route.

## Dal comando al secondo argomento di handle_result

| Helper | Risultato e opzioni |
| --- | --- |
| `respond(ctx, text)`, `no_response(ctx)` | Il primo emette `{:response, interaction, text, metadata}` al consumer nel messaggio `{Spectre.Server, pid, event}`. Il secondo termina in silenzio. Una risposta letterale non genera un callback di successo. |
| `generate(ctx, prompt, opts)` | `{:generated, %{text: text, proposals: proposals}}` con il servizio standard. `input:` e `assigns:` alimentano il prompt, `planning:` prepara proposte, `stream:` abilita lo stream, `preview:` accetta `:auto`, `:off` o `:required`. |
| `classify(ctx, input, opts)` | `{:classified, label}` oppure errore. `choices:` fornisce le alternative, `context:` aggiunge contesto. Il tuo callback sceglie cosa fare con l’etichetta. |
| `propose(ctx, operation, args, opts)` | Esito GAM, ad esempio `{:governed, %{outcome: %{status: :succeeded}}}`, `{:consent, :rejected}`, `{:consent, :expired}`, `{:governed_unknown, details}` o un errore. Verifica lo stato prima di annunciare il successo. Il timeout dell’effetto è configurato dall’host. |
| `call_actor(ctx, pid, request, opts)` | Il valore restituito da `GenServer.call`, oppure `{:error, reason}`. `timeout:` limita l’attesa del worker. |
| `delegate(ctx, mount, input, opts)` | `{:delegated, %{skill: mount, interaction: id}}` alla presa in carico. La risposta del figlio arriva separatamente come evento della Skill. |
| `await_input`, `await_reply`, `resolve_await` | `await_input(ctx, id, opts)` aspetta il prossimo input in primo piano. Il default risolve con `{:ok, input}`. `await_reply` aspetta in background; `resolve_await(ctx, id, result)` consegna quel risultato. Timeout di default 30 s; è ammesso `:infinity`. |
| Helper installato | Con un tool cognitivo arriva il valore proiettato dall’adapter. Per un effetto governato arriva l’esito GAM. `on_result:` sceglie la continuazione, `timeout:` si applica ai percorsi consentiti e `confirmation:` al percorso governato. |

Se ometti `on_result:`, per `generate`, `classify`, `propose`, `call_actor` e `delegate` il tag è il nome del comando. Per un’attesa è il suo ID, per un tool installato il nome dell’helper. Un tag come `:sent` può quindi ricevere sia successo sia errore. I risultati incerti richiedono verifica prima di ripetere un effetto.

Per personalizzare l’attesa usa `confirm_pending`, `reject_pending` o `explain_pending` con `pending.id`. Per cambiare argomento, `route_current_input(ctx, suspend: pending.id)` sospende l’attesa e reinstrada il turno; `resume_pending` la riprende. `close_pending`, `close_pending_after` e `cancel_pending_close` gestiscono la chiusura applicativa. La scadenza del consenso resta distinta. Consulta [routing e strategie](/it/docs/routing), [esempi di Skill e tool](/it/docs/recipes) e [approvazioni esterne](/it/docs/agent-to-agent).

## Personalizzare la policy e la durata di un’attesa

Se basta chiedere conferma ogni volta, usa `confirm: true` nella configurazione dell’operazione. Se la regola dipende dalla richiesta corrente, il Server può restituire da `handle_action/2` per esempio `{:confirm, %{message: "Confermare l’invio?", expires_in: 60_000}}`. Il messaggio accompagna il materiale della proposta. La durata è in millisecondi ed è limitata dalla policy dell’host.

Per un cambio di argomento, `close_pending_after(ctx, pending.id, 120_000, reason: :idle, if_revision: pending.revision)` pianifica la chiusura di quella versione dell’attesa. `reason:` spiega il motivo, `policy_ref:` identifica la regola dell’app, `if_revision:` evita di chiudere una versione successiva, `if_schedule:` permette di mirare alla pianificazione esatta. Il timer è del runtime per default; con `timer: :application` l’app possiede il risveglio OTP. [Esempi completi del ciclo di vita](https://github.com/elchemista/spectre/blob/0.4.0/docs/PENDING_LIFECYCLE.md).
