# Spectre 0.4 documentation

Build agents that recognize requests, use models and tools, and perform governed work in supervised Elixir processes.

Spectre separates recognition, conversation ownership and permission to act. A model can help understand a question, generate text or prepare a proposal. Your application still decides which operations exist, who may authorize them, how state persists and what counts as an observed result.

## Start with the architecture

```text
Stack                         Agent                         Server
installed capabilities   →    routes and intents      →    application callbacks
models, memory, tools         recognition evidence          conversation + workers
                                                                  │
                                               governed proposal  │
                                                                  ▼
                                                        Managed GAM
                                                 authority + human consent
                                                                  │
                                                     admitted Act → execution
                                                                  │
                                                         observed Outcome
```

**Stack** selects reusable capabilities. **Agent** declares recognition. **Server** owns the running conversation through ordinary OTP callbacks. Mounted Skills have their own Server processes and state while sharing the root agent's GAM Domain.

**GAM means Governed Act Model.** It defines the transition from a proposal to an authorized operation. Admission and execution are separate facts: permission to send an email does not prove that the email service accepted it. Read the [GAM manifesto](/en/governed-act-model), then the [architecture guide](/en/docs/architecture-gam).

## Choose a learning path

| Your goal | Read |
| --- | --- |
| Run the first conversation, without a model or database | [Getting started](/en/docs/getting-started) |
| Understand ownership, workers and approval | [Architecture and GAM](/en/docs/architecture-gam) |
| Combine patterns, similarity and model classification | [Routing](/en/docs/routing) |
| Review examples, generate embeddings and train a classifier | [Training](/en/docs/training) |
| Ask a human through a different agent | [Agent-to-agent](/en/docs/agent-to-agent) |
| Implement a provider or application integration | [Behaviours](/en/docs/behaviours) |
| Persist history, reduce historical RAM residency and recover | [Storage](/en/docs/storage) |
| Generate and diagnose an application | [Mix tasks](/en/docs/mix-tasks) |
| Choose optional libraries | [Ecosystem](/en/docs/ecosystem) |
| Build a complete workflow | [Recipes](/en/docs/recipes) |
| Verify behavior and operate the system | [Testing and production](/en/docs/testing-production) |
| Upgrade an existing application | [Migration from 0.3](/en/docs/migration) |

## What you need

Core requires Elixir `~> 1.19` and can run with neither a model nor a database. Add `{:spectre, "~> 0.4.0"}` to your dependencies. Models, browser drivers, transport credentials and database pools are host dependencies, installed only when needed.

The nine companion libraries are optional. Core does not require them to compile, run its tests or execute a RAM-only AgentServer. Their release versions are independent; consult the [ecosystem installation notes](/en/docs/ecosystem) before copying dependencies.

## How to read examples

The first guide contains a complete model-free example. Later fragments explicitly identify the Stack, provider, prompt or effect registration they require. Names such as `MyApp.Embeddings`, `MyApp.PrivateArchive` and `MyApp.MailClient` describe application adapters; they are not modules shipped by Spectre.

These guides describe the **0.4 AgentServer path**. The retained `Instance`, `Run`, Work/Vigil and definition-evolution APIs remain documented for existing applications, but do not replace the new Server lifecycle. See the [versioned API reference](https://hexdocs.pm/spectre/0.4.0/) for exact types and the [0.4 source guides](https://github.com/elchemista/spectre/tree/0.4.0/docs) for executable fixtures.
