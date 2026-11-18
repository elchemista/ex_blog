# Routing: patterns, vectors and classifiers

Combine seven recognition strategies and application-owned providers without confusing route confidence with permission.

To try a strategy, keep one route and inspect `ctx.routing` inside `handle_flow/3`. Change the wording while keeping the callback key the same. If you receive `:unmatched`, inspect `ctx.routing.reason`. Then follow [dispatch in the Server](/en/docs/server-callbacks).

## Seven complementary strategies

| Strategy | Evidence | Dependencies |
| --- | --- | --- |
| `:regex` | Explicit pattern on a route | `regex:` |
| `:bag` | Character-multiset similarity | `bag:` phrases; no model |
| `:jaro` | Short-string/spelling similarity | `jaro:` phrases; no model |
| `:intent_dataset` | Reviewed exact examples or compatible stored vectors | Dataset; encoder only for vector lookup |
| `:embedding` | Semantic similarity to declared route examples | `semantic_examples:` and an encoder |
| `:local_classifier` | Local classifier prediction | Configured adapter or trained artifacts |
| `:llm_classifier` | Model choice among visible declared intents | Configured classifier model |

Bag uses `String.bag_distance/2` on characters, not word tokens. Jaro uses `String.jaro_distance/2`. Neither understands meaning. An embedding encoder maps text to vectors. **Vettore indexes and searches vectors; it does not generate language embeddings.** Use compatible encoder/model/version/dimensions for stored examples and query vectors.

## Combine semantic matching and model classification

This Agent fragment adds provider bindings to the [first conversation](/en/docs/getting-started). `MyApp.Embeddings` and `MyApp.IntentModel` are application adapters configured below; the Server must implement both routes.

```elixir
defmodule MyApp.SupportAgent do
  use Spectre.Agent, stack: MyApp.AI, server: MyApp.SupportServer

  embedding MyApp.Embeddings
  classifier :llm, MyApp.IntentModel, timeout: 8_000

  router strategies: [:regex, :embedding, :llm_classifier]

  flow :support do
    on :pricing,
      regex: ~r/\b(price|pricing|cost)\b/i,
      semantic_examples: ["How much does a subscription cost?"]

    on :technical,
      semantic_examples: ["My API key stopped working", "I cannot sign in"]
  end
end
```

The regex recognizes a known pricing request cheaply. A different phrase can match by semantic similarity. When evidence is insufficient, the classifier can choose among declared labels. `:llm_classifier` enables arbitration fallback; it does not force a model call at its position in the list.

## Use the built-in ExFastembed adapter

You do not need to implement `MyApp.Embeddings` to use a local encoder. Core ships `Spectre.Classifier.Embeddings.ExFastembed`; add its optional backend dependency explicitly. This is the source revision pinned by core's real-embedding CI, not a claim about an independently published Hex release:

```elixir
{:ex_fastembed, github: "elchemista/ex_fastembed", ref: "02edfc604274077d8a02848dcfafd56797598d77"}
```

Follow the [backend's native build requirements](https://github.com/elchemista/ex_fastembed/blob/02edfc604274077d8a02848dcfafd56797598d77/README.md#installation). During application bootstrap, **before starting AgentServers**, load the model once and probe it; initial loading can download model files:

```elixir
adapter = Spectre.Classifier.Embeddings.ExFastembed
{:ok, dimensions} = adapter.load("intfloat/multilingual-e5-small")
{:ok, vector} = adapter.embed("How much is the subscription?")
true = length(vector) == dimensions
```

Then replace the Agent's host-module binding with:

```elixir
embedding Spectre.Classifier.Embeddings.ExFastembed, model: "intfloat/multilingual-e5-small"
```

Vettore is already a core dependency; this encoder and its model are not automatically installed or loaded. `embed/2` uses the active backend model: do not load or switch models per request. A later load replaces that model; keep the binding, stored vectors and profile/dimensions consistent. For hosted models, use a configured application adapter or the [Prism integration](/en/docs/ecosystem); configure credentials at runtime.

## Configure host providers

| Binding | Function | Success |
| --- | --- | --- |
| `embedding MyApp.Embeddings, opts` | `embed(text, opts)` | `{:ok, nonempty_numeric_vector}` |
| `classifier :local, MyApp.LocalClassifier, opts` | `classify(text, opts)` | `{:ok, %{label: ..., accepted?: ..., confidence: ..., margin: ...}}` |
| `classifier :llm, MyApp.IntentModel, opts` | `complete(prompt, opts)` | `{:ok, declared_label_as_text}` |

Each may return `{:error, reason}`. Local classifier scores must meet the router's thresholds; an accepted flag alone does not bypass arbitration. `Spectre.LLM` is the completion behaviour. Router embedding and local classification are documented function contracts, not invented `@behaviour` modules. The response-generation model can differ from the classifier.

With all adapters present, this is valid inside the Agent:

```elixir
classifier :local, MyApp.LocalClassifier, artifact_dir: "priv/intents"
router strategies: [:regex, :intent_dataset, :bag, :jaro,
                     :embedding, :local_classifier, :llm_classifier]
```

## Exact examples before vector search

A model-free dataset configuration can use:

```elixir
# Inside the Agent; no custom dataset module is required.
router strategies: [:regex, :intent_dataset], semantic_search?: false

flow :support do
  on :pricing,
    regex: ~r/^prices?$/i,
    semantic_examples: ["How much is a subscription?"],
    collect_intent: true
end
```

Exact recognition does not call an encoder. Online collected rows are unverified until reviewed. Adding text does not automatically create a vector or train a classifier. See [training](/en/docs/training).

The generated pipeline also appends dataset lookup when a route permits it. `semantic_cache?: false` disables that automatic lookup; `dataset_lookup: false` excludes an individual route. Do not configure `Spectre.Router.SemanticCache` as its own adapter: it is the dispatcher.

## Arbitration and fallback

The default arbitrator considers hard evidence, provider agreement and accepted scored evidence. Scores from different providers are not a universal probability scale. Tune thresholds and margins on a labeled corpus. Interrupts, current flow, scope, checks and `match_with:` determine which rules are visible. An adapter cannot create an undeclared handler.

Accepted hard evidence can skip later expensive providers. Bag and Jaro may still collect inexpensive evidence. To diagnose failure, handle `:unmatched` and inspect the routing reason:

```elixir
# Inside the Server.
def handle_flow(:unmatched, _input, ctx) do
  case ctx.routing.reason do
    :ambiguous -> respond(ctx, "Do you mean pricing or technical support?")
    :no_match -> respond(ctx, "Please describe what you need.")
    _ -> respond(ctx, "Recognition is temporarily unavailable; please clarify.")
  end
end
```

Provider errors and dataset misses are distinct. Recognition can recover through another strategy. For a custom source use [Router.Adapter](/en/docs/behaviours), and evaluate recognition without invoking handlers through `Spectre.Router.evaluate/2` or `mix spectre.eval`.

Use canonical strategy names in new code. Retained `:semantic_cache` and `:classifier` are aliases; legacy `:llm` does **not** enable LLM classification. `:arbitrate` and `:terminalize` are pipeline controls, not additional recognition strategies. See the [full router reference](https://github.com/elchemista/spectre/blob/0.4.0/docs/ROUTING.md) for thresholds and explicit pipelines.
