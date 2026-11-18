# Messaggi tra agenti e approvazione umana esterna

Collega agenti indipendenti mantenendo distinti autorità di esecuzione, autenticazione del trasporto e consenso umano.

Prima prova [il consenso con un solo Server](/it/docs/handlers). Qui il Server del cliente esegue ancora `propose` e riceve ancora `handle_result(tag, result, ctx)`. Cambia la destinazione della presentazione: il consumer del secondo agente mostra la richiesta e raccoglie la scelta della persona.

## L'agente del cliente chiede al tuo agente personale

Un cliente vuole che il proprio agente navighi su un sito, ma solo dopo la tua approvazione. Tu hai una chat separata con il tuo agente personale. È un'approvazione umana esterna, non una delega dell'autorità a un modello AI.

```text
AgentServer cliente / Domain A           AgentServer personale / Domain B
propone l'operazione browser
       │
Managed GAM congela la richiesta ──────► inbox di approvazione autenticata
       │                                il consumer mostra la richiesta esatta
       │                                la persona conferma o rifiuta
       ◄─────────────────────────────── decisione firmata e correlata
verifica prove + mandato originale
       │
ammette ed esegue, oppure attende/rifiuta
       │
registra l'Outcome osservato
```

Il Domain A conserva l'autorità di esecuzione. Il Domain B gestisce la conversazione con la persona. Una risposta esterna valida soddisfa un requisito di consenso; non amplia il mandato originale del cliente.

## Esegui l'esempio indipendente dal trasporto

Dal [checkout del core](https://github.com/elchemista/spectre/tree/0.4.0):

```sh
mix deps.get
mix run docs/examples/external_approval.exs
```

L'esempio avvia due AgentServer reali con Domain diversi. Un piccolo adapter a messaggi scambia mappe del protocollo e il consumer di test simula conferma e rifiuto umani. L'effetto browser è una fixture: non naviga su Internet. L'esempio verifica l'attesa del consenso e il rifiuto del replay di una risposta consumata. **Pulse non è necessario.**

## Implementa il contratto di trasporto

Il trasporto implementa `Spectre.Server.GAM.Managed.Approval.send_message/2` e restituisce `{:ok, receipt}` oppure `{:error, reason}`. Riceve mappe portabili e opzioni. Configuralo in `gam: [approvals: [transport: {Module, options}, ...]]`.

Per ogni operazione governata configura `confirm: true, approver: {:external, address}`. Il richiedente fissa Principal umano, indirizzo, chiave pubblica Ed25519, riferimento dell'autorizzazione e scadenza in `approvals.approvers`. Il Server personale configura il firmatario corrispondente. L'[esempio completo](https://github.com/elchemista/spectre/blob/0.4.0/docs/examples/external_approval.exs) mostra chiavi e configurazione: in produzione usa chiavi persistenti dell'applicazione, non nuove chiavi a ogni riavvio.

Autentica il peer prima di chiamare `Spectre.Server.receive_approval/2`. Questa API dell'host non autentica autonomamente il trasporto di rete. Un indirizzo di agente conosciuto non prova identità o mandato della persona.

## Quattro messaggi applicativi

| Messaggio | Significato |
| --- | --- |
| `approval.request` | Presentation congelata, identità/revisione della richiesta, vincoli, approvatore e scadenza |
| `approval.presented` | Conferma firmata del consumer fidato che ha mostrato la richiesta esatta |
| `approval.decision` | Conferma/rifiuto firmato e legato all'intera richiesta |
| `approval.cancelled` | Notifica autenticata del richiedente che l'attesa è stata chiusa |

Il consumer configurato nell'agente personale riceve:

```elixir
{Spectre.Server, personal_server, {:approval_request, request}}
```

La UI mostra `request["rendered_payload"]`, richiedente e scadenza. Dopo la visualizzazione effettiva chiama `Spectre.Server.approval_presented(personal_server, reference)`. Dopo una scelta distinta della persona autenticata chiama `Spectre.Server.approval_decide(personal_server, reference, :confirm)` oppure `:reject`. Usa il riferimento completo `%{id: request["id"], from: request["from"]}`. Il modello non deve provocare queste chiamate.

## La consegna non è consenso

Pulse può trasportare il protocollo attraverso peer autenticati, envelope e trasporti esistenti. La ricevuta tecnica **`accepted` significa acquisizione da parte del trasporto ricevente, non visualizzazione, approvazione umana, ammissione GAM o successo dell'esecuzione**. Vale anche per mailbox o adapter HTTP personalizzati.

Il ritorno `:ok` di `approval_presented` o `approval_decide` indica che la risposta firmata è stata salvata e messa in consegna. Successivi eventi `:approval_delivery` riportano `:accepted`, `:not_sent` o `:unknown`: nessuno è l'Outcome dell'effetto finale.

## Retry, scadenze e recovery

Le richieste vengono deduplicate per destinatario, ID e mittente; il contenuto immutabile deve coincidere. Le risposte umane usano transizioni di storage protette dalla revisione. Ripeti la stessa chiamata UI per reinviare la firma già salvata, non per creare una nuova decisione. Non ci sono retry di rete automatici.

Risposte contraffatte, conflittuali, scadute o consumate non autorizzano l'operazione. Una decisione firmata arrivata prima della conclusione della presentazione non può autorizzare immediatamente l'esecuzione. La cancellazione è best effort; la scadenza resta vincolante anche se la notifica si perde.

Dopo il riavvio del richiedente, l'attesa viene ripristinata sospesa e richiede una nuova presentation/richiesta. Un approvatore con storage persistente può ritrasmettere la scelta esatta salvata. Mantieni coerenti scadenze assolute e chiavi. La [guida a inbox e storage](https://github.com/elchemista/spectre/blob/0.4.0/docs/EXTERNAL_APPROVALS.md) descrive paginazione limitata, callback di manutenzione ed eventi di errore.

## Governa tutta la superficie dell'operazione

Se navigare richiede consenso, governa sia Lens `open` sia `look(url)`: guardare una URL può provocare navigazione. Il nome cognitivo di un helper non stabilisce un confine di permesso. La UI deve spiegare la conseguenza, non limitarsi a mostrare un digest.

Consulta la [guida adapter Pulse](https://github.com/elchemista/spectre_pulse/blob/main/docs/EXTERNAL_APPROVALS.md), i [behaviour](/it/docs/behaviours) e i [test degli errori](/it/docs/testing-production).
