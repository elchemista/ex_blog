# Task Mix e diagnostica

Usa i dodici task del core per generare, ispezionare, valutare e addestrare agenti, con requisiti espliciti per runtime e adapter.

Dopo il generatore apri `lib/my_app/support_agent.ex` per l’input riconosciuto e `lib/my_app/support_server.ex` per la risposta. Esegui `mix spectre.routes MyApp.SupportAgent` per verificare il nome compilato, poi il test generato per verificare che la callback si comporti come previsto.

## Genera l'architettura corrente

```sh
mix spectre.gen.agent MyApp.SupportAgent --server --dry-run
mix spectre.gen.agent MyApp.SupportAgent --server
mix spectre.routes MyApp.SupportAgent
mix spectre.doctor --agent MyApp.SupportAgent --strict
```

`--server` sceglie i template Agent/Server della 0.4. Senza quel flag, il generatore mantiene intenzionalmente lo stile Instance precedente. I generatori verificano il piano e non sovrascrivono file senza `--force`. Esegui il test generato prima di aggiungere provider o effetti.

## Tutti i dodici task del core

| Task | Esempio | Scopo e requisiti |
| --- | --- | --- |
| `spectre.gen.agent` | `mix spectre.gen.agent MyApp.SupportAgent --server` | Agent, Server e test del runtime; `--dry-run`, `--force` |
| `spectre.gen.installable` | `mix spectre.gen.installable MyApp.TextPackage` | Package installabile nello Stack e test; verifica contratti di risorse/tool |
| `spectre.gen.checkpoint_store` | `mix spectre.gen.checkpoint_store MyApp.Checkpoints` | Scheletro del **precedente Instance.CheckpointStore**, non del nuovo Server.Store |
| `spectre.routes` | `mix spectre.routes MyApp.SupportAgent --json` | Intenti, flow annidati/con scope e destinazioni Server; non esegue handler |
| `spectre.doctor` | `mix spectre.doctor --agent MyApp.SupportAgent --format json` | Diagnostica dei contratti compilati; `--strict` rifiuta anche warning |
| `spectre.eval` | `mix spectre.eval MyApp.SupportAgent test/fixtures/routing.jsonl` | Accuratezza e policy delle chiamate al classificatore; può usare i provider |
| `spectre.intent_dataset.export` | `mix spectre.intent_dataset.export MyApp.SupportAgent examples.jsonl` | Export degli esempi verificati; `--include-unverified`, `--source online\|all` |
| `spectre.intent_dataset.embed` | `mix spectre.intent_dataset.embed MyApp.SupportAgent examples.jsonl vectors.jsonl` | Prepara/riutilizza vettori compatibili con l'encoder configurato, senza training |
| `spectre.classifier.dataset` | `mix spectre.classifier.dataset MyApp.SupportAgent training/dataset.json --source training/raw.jsonl` | Costruisce il corpus etichettato; `--source` ripetibile |
| `spectre.classifier.download_model` | `mix spectre.classifier.download_model --model intfloat/multilingual-e5-small` | Scarica/carica l'encoder; richiede dipendenze e accesso al modello |
| `spectre.classifier.train` | `mix spectre.classifier.train training/dataset.json priv/intents` | Scrive artefatti del classificatore; richiede encoder e dati etichettati |
| `spectre.profile` | `mix spectre.profile --scenario restore_runs --runs 64 --iterations 5` | Profilo di avvio/ripristino **Instance**, non audit completo dei processi AgentServer |

Consulta `mix help <task>` per le opzioni della versione installata. La disponibilità del task non configura credenziali, scarica ogni dipendenza o crea il Repo applicativo.

## Valutazione del routing in CI

Con una route `:pricing` dichiarata, salva una fixture JSONL:

```json
{"id":"pricing-command","input":"What is the price?","expected_route":"pricing","expected_strategy":"regex","llm":"forbidden"}
```

Poi esegui:

```sh
mix spectre.eval MyApp.SupportAgent test/fixtures/routing.jsonl \
  --json tmp/routing-report.json --min-pass-rate 1.0
```

La valutazione usa la pipeline input/router configurata, ma non l'handler scelto, le normali scritture di memoria o l'esecuzione degli effetti. Embedding e classificatori possono consumare risorse del provider. Aggiungi negativi, ambiguità e casi con uso LLM vietato o richiesto. Verifica sia accuratezza sia chiamate superflue.

## Cosa verifica Doctor

Doctor del core verifica dichiarazioni e contratti compilati. Non è un controllo live di endpoint modello, database, browser o servizio email. Esegui separatamente diagnostiche dei package e prove applicative di connessione/recovery. Un report positivo non concede autorità GAM.

## Task rilevanti dei satelliti

Questi comandi esistono dopo aver installato la libreria proprietaria. Leggi l'help prima di usarli: i task operativi possono contattare servizi reali.

| Package | Task | Note |
| --- | --- | --- |
| Lens | `spectre.lens.doctor`, `spectre.lens.install` | Individuazione di driver/browser e installazione con checksum; può scaricare il browser |
| Ledger | `spectre_ledger.doctor`, `spectre_ledger.gen.migration` | Diagnostica backend e migrazione archivio; Server/GAM e proiezione richiedono anche le migrazioni separate documentate |
| Kinetic | `spectre_kinetic.extract`, `.compile`, `.show`, `.download_encoder`, `.train_classifier`, `.train_reranker` | Estrae/compila il catalogo azioni, ispeziona artefatti e prepara riconoscitori opzionali; i nomi abbreviati hanno prefisso `spectre_kinetic` |
| Beam | `beam.status`, `beam.doctor`, `beam.chat`, `beam.send`, `beam.tail` | Ispezione e comunicazione con gateway; chat/send e prove di consegna possono produrre lavoro esterno |
| Lab | `spectre_lab.doctor`, `spectre_lab.gen.test`, `spectre_lab.bundle.verify` | Diagnostica, scheletri di test offline e verifica dei bundle |
| Mnemonic | `spectre_mnemonic.repartition` | Migrazione esplicita dei record mediante piano applicativo; verifica e backup prima |

Directive, Prism e Pulse non richiedono un generatore Mix per l'installazione nello Stack. Separa test deterministici offline da download di modelli/browser, invii reali e migrazioni del database.

Vedi [training](/it/docs/training), [contratti di estensione](/it/docs/behaviours) e [profilazione](/it/docs/testing-production).
