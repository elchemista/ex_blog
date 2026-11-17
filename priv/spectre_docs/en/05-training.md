# Intent datasets, embeddings and training

Collect and review intent examples, prepare compatible vectors, and train local classifiers as separate operations.

## One dataset, several uses

`Spectre.IntentDataset` stores labeled intent examples, not cached model answers. A reviewed text-only row can recognize an exact input. Only rows with valid compatible embeddings enter vector lookup. Classifier training produces separate prediction artifacts.

```text
recognized input → eligible collection → unverified example
                                              │ review / relabel
                                              ▼
                                       verified labeled text
                                         │             │
                                    exact lookup   encoder → vectors
                                                       │
                                              vector index / training
```

Collection is useful before selecting an embedding model. It does not automatically retrain a classifier, verify an example or grant authority to execute its route.

## Declare collection policy

The following belongs inside an Agent with the relevant Stack, Server and provider bindings:

```elixir
embedding MyApp.Embeddings
classifier :local, MyApp.LocalClassifier, artifact_dir: "priv/intents"
classifier :llm, MyApp.IntentModel, timeout: 8_000

router strategies: [:regex, :intent_dataset, :embedding,
                     :local_classifier, :llm_classifier]

flow :support, defaults: [collect_intent: true] do
  on :pricing, semantic_examples: ["How much does a subscription cost?"]
  on :technical, semantic_examples: ["My API key stopped working"]
  on :delete_account, regex: ~r/^delete my account$/i,
    collect_intent: false, dataset_lookup: false, protected: true
end
```

`collect_intent: true` enables eligible collection under the configured policy. Sensitive or protected operations need a deliberate review policy; disable collection and lookup independently where appropriate. `protected: true` is not an execution mandate.

## Review online examples

With `MyApp.SupportAgent` loaded:

```elixir
{:ok, row} = Spectre.IntentDataset.put(
  "I need a custom subscription quotation",
  %{label: :pricing, strategy: :llm_classifier},
  agent: MyApp.SupportAgent)

{:ok, examples} = Spectre.IntentDataset.examples(MyApp.SupportAgent)
{:ok, verified} = Spectre.IntentDataset.verify(MyApp.SupportAgent, row.id)
```

Use the facade's `relabel`, `update_example`, `delete`, `snapshot` and `load_snapshot` operations for corpus maintenance. Unverified online examples are excluded from normal lookup. Explicit `lookup: [include_unverified: true]` changes that policy; it should be an intentional experiment, not an unnoticed default.

## Export and embed without training

```sh
mix spectre.intent_dataset.export MyApp.SupportAgent examples.jsonl
mix spectre.intent_dataset.embed MyApp.SupportAgent examples.jsonl vectors.jsonl
```

Export includes verified examples by default. `--include-unverified` explicitly exports pending review; `--source all` also includes static route examples. The embedding task uses the Agent/Stack's configured encoder. It reuses compatible stored vectors and generates only missing ones. Output is replaced after the complete batch succeeds.

Sources support JSON arrays or JSONL with `text` and `label`:

```json
{"text":"How much is a subscription?","label":"pricing"}
{"text":"My API key stopped working","label":"technical"}
```

Every label must resolve to an eligible declared route. A dataset cannot manufacture route atoms or handlers. Preserve model identity, version, dimension and metric compatibility. Unknown or incompatible vector profiles must be repaired or re-embedded, not silently relabeled. A zero vector is not a substitute for missing encoder output.

For a local encoder without a custom module, follow the [built-in ExFastembed setup](/en/docs/routing#use-the-built-in-exfastembed-adapter): add the pinned optional backend, load the selected model once at bootstrap, bind the shipped adapter and check the returned vector dimensions. Dataset embedding does not provision or switch that runtime model for you.

## Train a local classifier

These commands require the host embedding dependencies and may download a model:

```sh
mix spectre.classifier.dataset MyApp.SupportAgent \
  training/support/dataset.json --source training/raw/support.jsonl
mix spectre.classifier.download_model --model intfloat/multilingual-e5-small
mix spectre.classifier.train training/support/dataset.json priv/spectre/support
```

Bind the resulting artifacts to the configured local classifier. One supported core configuration is:

```elixir
config :spectre, :classifier,
  artifact_dir: "priv/spectre/support",
  encoder_model: "intfloat/multilingual-e5-small",
  embedding_adapter: Spectre.Classifier.Embeddings.ExFastembed
```

The trainer also writes the retained `semantic_cache.jsonl` companion containing examples and saved vectors. This artifact filename does not turn the dataset into a response cache. Classifier centroid/example indexes and semantic row lookup are different consumers of compatible vectors.

**Vettore supplies indexing and search, not text encoding.** Quantized search can use Hamming candidates and full-metric reranking. Select CPU/GPU and index settings for the installed Vettore version and measured workload. Changing the classifier does not change the response-generation model.

## Evaluate before deployment

Reserve held-out examples, including ambiguity, typos, negatives and provider failures. Use `mix spectre.eval` to check accepted labels and unnecessary model calls. Keep data splits and encoder/artifact versions reproducible. Review collection privacy separately from routing accuracy.

See [Mix tasks](/en/docs/mix-tasks), [the official training guide](https://github.com/elchemista/spectre/blob/0.4.0/docs/TRAINING.md) and [testing](/en/docs/testing-production).
