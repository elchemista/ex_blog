# Routing: pattern, vettori e classificatori

Combina sette strategie di riconoscimento e provider applicativi senza confondere la confidenza di una route con un permesso.

Per provare una strategia, mantieni una sola route e osserva `ctx.routing` dentro `handle_flow/3`. Cambia la frase lasciando invariata la chiave della callback. Se arriva `:unmatched`, leggi `ctx.routing.reason`. Dopo il riconoscimento segui [il percorso nel Server](/it/docs/server-callbacks).

## Sette strategie complementari

| Strategia | Prova utilizzata | Dipendenze |
| --- | --- | --- |
| `:regex` | Pattern esplicito sulla route | `regex:` |
| `:bag` | Similarità tra insiemi di caratteri con molteplicità | Frasi `bag:`, nessun modello |
| `:jaro` | Similarità tra stringhe brevi o con errori | Frasi `jaro:`, nessun modello |
| `:intent_dataset` | Esempi esatti verificati o vettori compatibili salvati | Dataset; encoder solo per ricerca vettoriale |
| `:embedding` | Similarità semantica con gli esempi della route | `semantic_examples:` e un encoder |
| `:local_classifier` | Predizione di un classificatore locale | Adapter configurato o artefatti addestrati |
| `:llm_classifier` | Scelta del modello tra intenti dichiarati visibili | Modello di classificazione configurato |

Bag usa `String.bag_distance/2` sui caratteri, non sui token delle parole. Jaro usa `String.jaro_distance/2`. Nessuno dei due comprende il significato. Un encoder trasforma il testo in vettori. **Vettore indicizza e cerca vettori; non genera embedding linguistici.** Esempi e query devono usare encoder, modello, versione e dimensioni compatibili.

## Combina similarità semantica e classificazione con modello

Questo frammento Agent estende l’[esempio della prima conversazione](/it/docs/getting-started). `MyApp.Embeddings` e `MyApp.IntentModel` sono adapter applicativi descritti sotto; il Server deve implementare entrambe le route.

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

La regex riconosce una domanda di prezzo esplicita con un costo ridotto. Altre formulazioni possono corrispondere per similarità semantica. Se le prove non bastano, il classificatore sceglie tra le label dichiarate. `:llm_classifier` abilita il fallback nell'arbitraggio: non forza una chiamata al modello in quella posizione della lista.

## Usa l'adapter ExFastembed fornito dal core

Per un encoder locale non devi implementare `MyApp.Embeddings`. Il core fornisce `Spectre.Classifier.Embeddings.ExFastembed`; aggiungi esplicitamente il backend opzionale. Questa è la revisione sorgente fissata dalla CI reale di embedding del core, non una presunta release Hex del backend:

```elixir
{:ex_fastembed, github: "elchemista/ex_fastembed", ref: "02edfc604274077d8a02848dcfafd56797598d77"}
```

Segui i [requisiti di compilazione nativa](https://github.com/elchemista/ex_fastembed/blob/02edfc604274077d8a02848dcfafd56797598d77/README.md#installation). Nel bootstrap applicativo, **prima di avviare AgentServer**, carica il modello una volta e provalo; il primo caricamento può scaricare i file del modello:

```elixir
adapter = Spectre.Classifier.Embeddings.ExFastembed
{:ok, dimensions} = adapter.load("intfloat/multilingual-e5-small")
{:ok, vector} = adapter.embed("How much is the subscription?")
true = length(vector) == dimensions
```

Sostituisci poi il binding dell'encoder nell'Agent con:

```elixir
embedding Spectre.Classifier.Embeddings.ExFastembed, model: "intfloat/multilingual-e5-small"
```

Vettore è già una dipendenza del core; encoder e modello non vengono installati o caricati automaticamente. `embed/2` usa il modello attivo: non caricarlo o cambiarlo a ogni richiesta. Un caricamento successivo lo sostituisce; mantieni coerenti binding, vettori salvati, profilo e dimensioni. Per modelli remoti usa un adapter applicativo o l'[integrazione Prism](/it/docs/ecosystem), con credenziali nel runtime.

## Configura i provider applicativi

| Binding | Funzione | Risultato positivo |
| --- | --- | --- |
| `embedding MyApp.Embeddings, opts` | `embed(text, opts)` | `{:ok, vettore_numerico_non_vuoto}` |
| `classifier :local, MyApp.LocalClassifier, opts` | `classify(text, opts)` | `{:ok, %{label: ..., accepted?: ..., confidence: ..., margin: ...}}` |
| `classifier :llm, MyApp.IntentModel, opts` | `complete(prompt, opts)` | `{:ok, label_dichiarata_come_testo}` |

Tutti possono restituire `{:error, reason}`. I punteggi del classificatore locale devono superare le soglie del router: il solo flag di accettazione non evita l'arbitraggio. Il behaviour di completamento è `Spectre.LLM`. Embedding del router e classificatore locale sono contratti di funzioni documentati, non moduli `@behaviour` da inventare. Il modello di generazione può essere diverso da quello di classificazione.

Con tutti gli adapter disponibili puoi dichiarare nell'Agent:

```elixir
classifier :local, MyApp.LocalClassifier, artifact_dir: "priv/intents"
router strategies: [:regex, :intent_dataset, :bag, :jaro,
                     :embedding, :local_classifier, :llm_classifier]
```

## Esempi esatti prima della ricerca vettoriale

Un dataset senza modelli può usare:

```elixir
# Dentro Agent; non serve un modulo dataset personalizzato.
router strategies: [:regex, :intent_dataset], semantic_search?: false

flow :support do
  on :pricing,
    regex: ~r/^prices?$/i,
    semantic_examples: ["How much is a subscription?"],
    collect_intent: true
end
```

Il riconoscimento esatto non chiama un encoder. Le righe raccolte online restano non verificate fino alla revisione. Aggiungere testo non produce automaticamente vettori né addestra un classificatore. Vedi [training](/it/docs/training).

La pipeline generata aggiunge anche la ricerca nel dataset quando una route la permette. `semantic_cache?: false` disattiva questa aggiunta; `dataset_lookup: false` esclude una singola route. Non usare `Spectre.Router.SemanticCache` come adapter di sé stesso: è il dispatcher.

## Arbitraggio e fallback

L'arbitro predefinito considera prove forti, accordo tra provider e prove con punteggi sufficienti. I punteggi di provider diversi non sono probabilità universalmente confrontabili. Regola soglie e margini su un corpus etichettato. Interrupt, flow corrente, scope, controlli e `match_with:` stabiliscono quali regole sono visibili. Nessun adapter può creare un handler non dichiarato.

Una prova forte accettata può evitare provider costosi successivi. Bag e Jaro possono comunque raccogliere prove economiche. Per distinguere gli errori gestisci `:unmatched` e leggi il motivo:

```elixir
# Dentro Server.
def handle_flow(:unmatched, _input, ctx) do
  case ctx.routing.reason do
    :ambiguous -> respond(ctx, "Intendi prezzi o assistenza tecnica?")
    :no_match -> respond(ctx, "Descrivi cosa ti serve.")
    _ -> respond(ctx, "Riconoscimento temporaneamente indisponibile: puoi chiarire?")
  end
end
```

Un errore del provider è diverso da un esempio assente. Un'altra strategia può comunque riuscire. Per una nuova sorgente usa [Router.Adapter](/it/docs/behaviours); per valutare il riconoscimento senza chiamare gli handler usa `Spectre.Router.evaluate/2` oppure `mix spectre.eval`.

Nel nuovo codice usa i nomi canonici. `:semantic_cache` e `:classifier` restano alias; il vecchio `:llm` **non** abilita la classificazione LLM. `:arbitrate` e `:terminalize` controllano la pipeline, non sono altre strategie. Il [riferimento completo](https://github.com/elchemista/spectre/blob/0.4.0/docs/ROUTING.md) descrive soglie e pipeline esplicite.
