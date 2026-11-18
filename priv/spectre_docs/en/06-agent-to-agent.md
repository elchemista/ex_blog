# Agent messaging and external human approval

Connect independent agents while keeping execution authority, transport authentication and human consent separate.

First try [consent with one Server](/en/docs/handlers). Here the customer Server still calls `propose` and receives `handle_result(tag, result, ctx)`. The destination of the presentation changes: the second agent’s consumer displays it and collects the human choice.

## A customer agent asks your personal agent

A customer wants its agent to browse a website, but only after you approve. You have a separate chat with your personal agent. This is an external human approval, not delegation of authority to an AI model.

```text
Customer AgentServer / Domain A          Personal AgentServer / Domain B
propose browser operation
       │
Managed GAM freezes request ───────────► authenticated approval inbox
       │                                consumer renders exact request
       │                                human confirms or rejects
       ◄─────────────────────────────── signed, correlated decision
verify evidence + original mandate
       │
admit and execute, or keep/refuse wait
       │
record observed Outcome
```

Domain A retains execution authority. Domain B carries the human conversation. A valid external reply can satisfy a consent requirement; it cannot broaden the customer's original mandate.

## Run the transport-independent example

From the [core source checkout](https://github.com/elchemista/spectre/tree/0.4.0):

```sh
mix deps.get
mix run docs/examples/external_approval.exs
```

This starts two real AgentServers with different Domains. A small mailbox adapter exchanges protocol maps, and the test consumer simulates human confirmation and rejection. The browser effect is a fixture; it does not navigate the public web. The example asserts that execution waits and a consumed reply cannot be reused. **Pulse is not required.**

## Implement the transport contract

A transport implements `Spectre.Server.GAM.Managed.Approval.send_message/2`, returning `{:ok, receipt}` or `{:error, reason}`. It receives portable protocol maps and options. Bind it under `gam: [approvals: [transport: {Module, options}, ...]]`.

For each governed operation configure `confirm: true, approver: {:external, address}`. The requester pins the intended human Principal, address, Ed25519 public key, authorization reference and expiry in `approvals.approvers`. The personal Server configures the matching signer. The [complete example](https://github.com/elchemista/spectre/blob/0.4.0/docs/examples/external_approval.exs) contains the complete key/configuration shape; use application-owned durable keys, not freshly generated production keys on every restart.

Authenticate incoming peers before calling `Spectre.Server.receive_approval/2`. That public host API does not authenticate the network transport by itself. A known agent address proves neither the human's identity nor their mandate.

## Four application messages

| Message | Meaning |
| --- | --- |
| `approval.request` | Frozen presentation, request identity/revision, bindings, intended approver and expiry |
| `approval.presented` | Signed trusted-consumer acknowledgement that the exact request was shown |
| `approval.decision` | Signed confirm/reject bound to that complete request |
| `approval.cancelled` | Authenticated requester notification that its wait closed |

The personal agent's configured consumer receives:

```elixir
{Spectre.Server, personal_server, {:approval_request, request}}
```

The UI displays `request["rendered_payload"]`, requester and expiry. After actual rendering it calls `Spectre.Server.approval_presented(personal_server, reference)`. After the authenticated human's distinct choice it calls `Spectre.Server.approval_decide(personal_server, reference, :confirm)` or `:reject`. Use the full reference `%{id: request["id"], from: request["from"]}`. A model must never drive these calls.

## Delivery is not consent

Pulse can carry this application protocol over its authenticated peers, envelopes and transports. Its technical **`accepted` receipt means acquisition by the receiving transport, not rendering, human approval, GAM admission or execution success**. The same separation applies to a mailbox or custom HTTP adapter.

`approval_presented` and `approval_decide` returning `:ok` means that the exact signed response was stored and queued. Later `:approval_delivery` events report `:accepted`, `:not_sent` or `:unknown`; none is the final effect Outcome.

## Retries, deadlines and recovery

Requests deduplicate by receiver, request ID and sender; their immutable content must match. Human replies use fenced storage transitions. Retry the same UI call to resend the identical stored signature, not to create a new decision. There are no automatic network retries.

Reject forged, conflicting, expired or consumed decisions. A signed decision arriving before successful presentation completion cannot immediately authorize execution. Cancellation is best effort; expiry remains binding even if the cancellation message is lost.

A requester restart restores its consent wait suspended and needs a fresh presentation/request to resume. An approver with durable storage can resend its exact stored choice. Keep absolute expiry and signer keys consistent across restarts. The [inbox and storage guide](https://github.com/elchemista/spectre/blob/0.4.0/docs/EXTERNAL_APPROVALS.md) describes bounded pagination, application maintenance hooks and storage-error events.

## Cover the complete operation surface

If navigation requires consent, govern both Lens `open` and `look(url)` paths: looking at a URL can navigate too. A cognitive helper name is not a permission boundary. The UI must explain the consequence, not merely display a digest.

See [Pulse's adapter guide](https://github.com/elchemista/spectre_pulse/blob/main/docs/EXTERNAL_APPROVALS.md), [behaviours](/en/docs/behaviours) and [failure testing](/en/docs/testing-production).
