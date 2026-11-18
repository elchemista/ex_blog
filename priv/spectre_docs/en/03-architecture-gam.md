# Architecture and the Governed Act Model

Understand Stack, Agent, Server and GAM before connecting an agent to consequential operations.

## Three application responsibilities

| Component | Owns | Does not establish |
| --- | --- | --- |
| Stack | Installed capabilities, immutable tool descriptors and supervised resources | Permission to execute every installed tool |
| Agent | Flows, intents, recognition providers and mounted Skill declarations | A running conversation or human consent |
| Server | Application callbacks, Context, pending work and result continuations | Authority merely because a handler matched |

The Server runtime owns the GenServer. Helpers such as `generate`, `classify`, `propose` and installed tool helpers append commands to the returned Context. Slow cognition and effects run in workers; results return to a named continuation. Checkpoint acquisition remains an ordered durability barrier, so storage latency still matters.

Skills mounted with a `server:` binding run in separate Server processes with independent assigns, workers and checkpoints. They share the root GAM Domain and the mount's restrictions. Two independent AgentServers instead normally have two independent Domains. This distinction matters for both supervision and external approvals.

## What GAM means

**Governed Act Model** is the model for authorizing consequential work. The [manifesto](/en/governed-act-model) defines the principles; Spectre implements the pure kernel and provides Managed GAM as its AgentServer integration.

The kernel checks authority and recorded facts. Managed GAM constructs candidates, presentations and evidence, coordinates storage and invokes an executor after admission. A model's fluent explanation, classifier confidence or transport receipt cannot substitute for authority.

| Term | Practical meaning |
| --- | --- |
| Principal | The subject to which authority or evidence is attributed |
| Mandate and Scope | Which operations that authority permits and under what constraints |
| Candidate | The concrete proposed operation and frozen arguments |
| Presentation | The exact consequence material shown when consent is needed |
| Evidence | An admissible recorded fact, including properly bound human consent |
| Decision / admission | Whether the proposal satisfies the applicable authority and evidence |
| Act and Attempt | The admitted operation and its concrete execution attempt |
| Outcome | What was actually observed after execution |
| Duty | A recorded obligation that can outlive a conversational wait |

A Domain orders its history and admission. Installed capabilities and transport adapters do not modify the kernel's rules.

## Example: prepare an email, then ask to send it

After registering an email effect, the root permits its operation:

```elixir
# Fragment of Spectre.Server.start_link/1 options.
identity: %{subject: "customer-42"},
consumer: chat_process,
gam: [operations: %{{:kinetic, :send_email} => [confirm: true]}]
```

The corresponding Server proposes the concrete draft:

```elixir
# Callback clauses; require the registered {:kinetic, :send_email} effect.
def handle_flow({:mail, :send}, _input, ctx) do
  propose(ctx, {:kinetic, :send_email},
    %{"to" => ctx.assigns.recipient, "body" => ctx.assigns.draft},
    on_result: :sent)
end

def handle_result(:sent, {:governed, %{outcome: %{status: :succeeded}}}, ctx),
  do: respond(ctx, "The mail service confirmed the operation.")

def handle_result(tag, result, ctx), do: super(tag, result, ctx)
```

This fragment is not a complete mail client: Kinetic's ActionProvider, the effect registration, credentials and the application's permitted authority must exist. See [tools and recipes](/en/docs/recipes).

In the code, `:mail` comes from `flow :mail` and `:send` from `on :send`. The command requests execution of `{:kinetic, :send_email}`. You write the tag `:sent` in `on_result:`; it comes back as the first argument even on rejection. The second argument is the actual result. To see the registration and consumer code too, [run the full core-only path](/en/docs/handlers).

## Consent has a rendering boundary

The authenticated consumer renders the exact Presentation, acknowledges that rendering and submits the human's separate choice. Approving a draft authorizes that draft under the existing mandate; changing recipient or content requires the appropriate fresh proposal. Do not drive the human decision API from model output.

A local consumer uses the public `presented` and `decide` APIs. External human approval transports the same requirement to another agent without moving execution authority. See [agent-to-agent approval](/en/docs/agent-to-agent).

## Preserve uncertain outcomes

Admission success and execution success are separate. An external service can time out after applying an effect. Record an ambiguous result and reconcile using the service's receipts or idempotency mechanism. Do not describe a timeout as proof that nothing happened, and do not automatically repeat a nonrepeatable effect.

GAM supplies a boundary your host must use. If application code directly invokes an email client or browser outside that boundary, no library can retroactively govern the operation. Define the complete governed surface, including navigation performed through a tool that otherwise looks cognitive.

Continue with [Managed GAM's exact configuration](https://github.com/elchemista/spectre/blob/0.4.0/docs/MANAGED_GAM.md), [storage](/en/docs/storage) and [testing](/en/docs/testing-production).
