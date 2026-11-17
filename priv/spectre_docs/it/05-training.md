# Dataset di intenti, embedding e training

Raccogli e verifica esempi di intenti, prepara vettori compatibili e addestra classificatori locali come operazioni distinte.

## Un dataset, diversi utilizzi

`Spectre.IntentDataset` conserva esempi etichettati di intenti, non risposte del modello in cache. Una riga verificata di solo testo può riconoscere un input esatto. Alla ricerca vettoriale partecipano solo righe con embedding validi e compatibili. Il training del classificatore produce artefatti di predizione separati.

```text
input riconosciuto → raccolta ammessa → esempio non verificato
                                              │ revisione / nuova etichetta
                                              ▼
                                      testo etichettato verificato
                                         │             │
                                   confronto esatto  encoder → vettori
                                                       │
                                              indice vettoriale / training
```

La raccolta è utile anche prima di scegliere il modello di embedding. Non riaddestra automaticamente, non verifica gli esempi e non concede autorità per eseguire la route.

## Dichiara la policy di raccolta

Il frammento va dentro un Agent con Stack, Server e provider corrispondenti:

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

`collect_intent: true` abilita la raccolta ammissibile secondo la policy configurata. Operazioni sensibili o protette richiedono una scelta esplicita di revisione: puoi disabilitare separatamente raccolta e lookup. `protected: true` non equivale a un mandato di esecuzione.

## Verifica gli esempi online

Con `MyApp.SupportAgent` caricato:

```elixir
{:ok, row} = Spectre.IntentDataset.put(
  "I need a custom subscription quotation",
  %{label: :pricing, strategy: :llm_classifier},
  agent: MyApp.SupportAgent)

{:ok, examples} = Spectre.IntentDataset.examples(MyApp.SupportAgent)
{:ok, verified} = Spectre.IntentDataset.verify(MyApp.SupportAgent, row.id)
```

Usa `relabel`, `update_example`, `delete`, `snapshot` e `load_snapshot` della facade per gestire il corpus. Gli esempi online non verificati sono esclusi dal lookup normale. `lookup: [include_unverified: true]` cambia esplicitamente la policy: deve essere una scelta consapevole, non un default nascosto.

## Esporta e prepara i vettori senza training

```sh
mix spectre.intent_dataset.export MyApp.SupportAgent examples.jsonl
mix spectre.intent_dataset.embed MyApp.SupportAgent examples.jsonl vectors.jsonl
```

L'export include per default gli esempi verificati. `--include-unverified` include quelli in attesa di revisione; `--source all` aggiunge gli esempi statici delle route. Il task di embedding usa l'encoder dell'Agent/Stack, riutilizza i vettori compatibili e genera solo quelli mancanti. Sostituisce il file di destinazione dopo il successo dell'intero batch.

Le sorgenti supportano array JSON o righe JSONL con `text` e `label`:

```json
{"text":"How much is a subscription?","label":"pricing"}
{"text":"My API key stopped working","label":"technical"}
```

Ogni label deve identificare una route dichiarata e ammessa. Il dataset non crea atom o handler. Mantieni compatibili identità e versione del modello, dimensione e metrica. Un profilo vettoriale sconosciuto o incompatibile va corretto o rigenerato, non semplicemente rinominato. Un vettore nullo non sostituisce un embedding mancante.

Per un encoder locale senza moduli personalizzati segui il [setup ExFastembed del core](/it/docs/routing#usa-ladapter-exfastembed-fornito-dal-core): aggiungi il backend opzionale fissato, carica il modello una volta nel bootstrap, collega l’adapter fornito e verifica le dimensioni del vettore. Il task di embedding del dataset non configura o cambia quel modello runtime al posto tuo.

## Addestra un classificatore locale

Questi comandi richiedono le dipendenze di embedding e possono scaricare un modello:

```sh
mix spectre.classifier.dataset MyApp.SupportAgent \
  training/support/dataset.json --source training/raw/support.jsonl
mix spectre.classifier.download_model --model intfloat/multilingual-e5-small
mix spectre.classifier.train training/support/dataset.json priv/spectre/support
```

Collega gli artefatti al classificatore locale. Una configurazione supportata dal core è:

```elixir
config :spectre, :classifier,
  artifact_dir: "priv/spectre/support",
  encoder_model: "intfloat/multilingual-e5-small",
  embedding_adapter: Spectre.Classifier.Embeddings.ExFastembed
```

Il trainer scrive anche il file compatibile `semantic_cache.jsonl`, con esempi e vettori salvati. Il nome storico del file non rende il dataset una cache di risposte. Indici del classificatore e lookup semantico delle righe sono utilizzatori distinti dei vettori.

**Vettore fornisce indici e ricerca, non l'encoding del testo.** La ricerca quantizzata può selezionare candidati con distanza di Hamming e riordinarli con la metrica completa. Scegli opzioni CPU/GPU e indici in base alla versione installata e al carico misurato. Cambiare classificatore non cambia il modello di generazione.

## Valuta prima del rilascio

Tieni separati esempi di valutazione con ambiguità, errori di scrittura, negativi e guasti dei provider. `mix spectre.eval` verifica label e chiamate superflue al modello. Conserva split dei dati e versioni di encoder e artefatti. Valuta la riservatezza della raccolta separatamente dall'accuratezza.

Consulta [task Mix](/it/docs/mix-tasks), [guida ufficiale al training](https://github.com/elchemista/spectre/blob/0.4.0/docs/TRAINING.md) e [test](/it/docs/testing-production).
