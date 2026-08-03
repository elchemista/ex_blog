# Showcase: redazione agentica con Spectre

Questo progetto usa Spectre come macchina applicativa, non come semplice chat.
Il modello propone testo; flow, skill, policy, stato ed effetti decidono cosa può
succedere davvero. Il risultato è un editor Telegram conversazionale che resta
deterministico nei passaggi sensibili e osservabile nei test.

## Mappa delle responsabilità

```text
ExGram / Telegram
└── Spectre Beam: normalizzazione del canale e identità autenticata
    └── Spectre Agent
        ├── skill Reader: lettura, ricerca e audit del blog
        ├── skill Editorial: workflow, generazione e mutazioni protette
        └── skill Operations: configurazione, budget e sync Git
            ├── Spectre Prism: scelta del livello OpenRouter
            ├── Spectre Kinetic: AL → azione tipizzata
            └── Spectre Policy: conferma → effetto eseguibile
```

La separazione è intenzionale:

- Beam capisce da quale canale arriva un messaggio, senza conoscere il dominio
  editoriale;
- la skill editoriale possiede conversazione e stato, senza incorporare Git o
  HTTP;
- Prism/OpenRouter generano valori, ma non avanzano il workflow e non scrivono
  file;
- Kinetic traduce soltanto Action Language valida nel catalogo `@al`;
- Spectre applica policy, persistenza, idempotenza ed esecuzione;
- `ExBlog.Content.Writer` resta l’unico confine di scrittura del Markdown.

## Flow dentro flow

La creazione è modellata in `ExBlog.Agent.Skills.Editorial` come una skill che
contiene il flow `:editorial`, il sotto-flow `:article_creation` e cinque leaf
flow:

```text
/create
  → article_brief
  → article_language
  → article_category ── “genera categoria” → OpenRouter fast
  → article_title    ── “genera titolo”    → OpenRouter balanced
  → article_seo      ── “genera SEO” | “salta”
  → CREATE ARTICLE ...
  → policy di conferma
  → OpenRouter deep per il corpo
  → OpenRouter balanced per SEO/tag, se richiesto
  → Writer → Git → rebuild ETS
```

`current_flow` e `current_scope` vengono salvati dallo state store DETS. Il plug
`CreationContinuation` osserva quel cursore e assegna le risposte libere al leaf
corretto senza spendere una classificazione LLM a ogni campo. Gli interrupt
globali `/cancel` e `/attach-image` conservano la precedenza e, dopo una foto,
il cursore resta esattamente sul passaggio precedente.

Questa è una proprietà utile di Spectre: un flow può esprimere la forma della
conversazione, mentre gli interrupt gestiscono eventi ortogonali senza spargere
condizionali nel trasporto Telegram.

## Generazione AI a grana fine

L’amministratore sceglie campo per campo:

| Parte | Comando nel flow | Livello | Effetto immediato |
| --- | --- | --- | --- |
| categoria | `genera categoria` | fast | aggiorna solo stato Spectre |
| titolo | `genera titolo` | balanced | aggiorna solo stato Spectre |
| corpo | sempre generato dopo conferma | deep | prepara il Markdown |
| SEO e tag | `genera SEO` | balanced | aggiunge front matter al nuovo draft |
| SEO esistente | `/seo it slug-articolo` | balanced | update Git protetto |
| traduzione | `/translate ...` | deep | crea un nuovo draft protetto |

Le generazioni intermedie passano da `ExBlog.Agent.EditorialAI`. È un leaf
read-only: restituisce un singolo valore limitato, non possiede lo stato e non
può mutare la repository. Il corpo e la SEO vengono invece creati dentro
`ExBlog.Agent.Actions.create_article/2`, dopo che Spectre ha ottenuto la
conferma. Così un rifiuto non produce un articolo parziale.

I prompt non sono stringhe concatenate nei callback. Sono template HEEx in
`lib/ex_blog_web/prompts`, divisi tra:

- `renderers/` per richieste OpenRouter riusabili;
- `skills/editorial/` per risposte e richieste del workflow;
- `skills/editorial/policies/` per il confine di conferma.

Ogni valore dinamico attraversa `ExBlogWeb.Prompt.escape_text/2`, che applica
redazione credenziali, limite di lunghezza ed escaping HTML prima del modello.

## Kinetic e `@al`

Il catalogo operativo vive nel codice Elixir in
`ExBlog.Agent.KineticActions`. `use SpectreKinetic` estrae nome, parametri,
tipi, documentazione ed esempi direttamente da `@al`, `@spec` e `@doc`.

Il wizard non costruisce una mappa da eseguire a mano. Produce una frase AL
canonica simile a questa:

```text
CREATE ARTICLE TITLE="Flow affidabili" LANG="it" CATEGORY="AI"
BRIEF="..." GENERATE_SEO=true
COVER="/images/articles/<sha256>.jpg" COVER_ALT="Schema del workflow"
```

Kinetic deve risolverla contro il catalogo tipizzato. Solo dopo Spectre crea un
effetto con owner e scope della skill editoriale e applica
`:editorial_confirmation`. Il provider locale chiama l’implementazione di
dominio soltanto quando l’effetto è approvato ed eseguibile.

Questa divisione permette di aggiungere sinonimi AL o migliorare il modello di
selezione senza spostare la sicurezza nel prompt.

## Foto Telegram come asset editoriale

Una foto segue un percorso separato dal testo, ma rientra nello stesso agent:

```text
sender_id == admin
  → Beam decodifica :image
  → metadati minimi: file_id, size, caption redatta
  → interrupt ATTACH_ARTICLE_IMAGE
  → verifica che article_creation sia attivo
  → ExGram.download_media/3
  → controllo dimensione e magic bytes
  → nome SHA-256, mai il filename dell’utente
  → priv/static/images/articles/<sha256>.<ext>
  → cover + cover_alt nel workflow
  → front matter Markdown dopo conferma
```

I byte non entrano in DETS, memoria, prompt o chat history. Il riferimento TDLib
è transitorio e il download avviene solo dopo il gate numerico dell’admin e la
verifica del flow attivo. Sono ammessi JPEG, PNG, WebP e GIF fino a 10 MB; SVG e
documenti arbitrari sono rifiutati.

La copia pubblica richiesta vive in `priv/static/images/articles`. Una copia
content-addressed viene mantenuta anche in
`$EX_BLOG_DATA_DIR/assets/images/articles` e ripristinata in `priv` a ogni boot,
perché la directory di una release viene sostituita durante un deploy. Il path
pubblico `/images/articles/...` rimane quindi stabile nel Markdown.

La didascalia Telegram diventa `cover_alt`. Se manca, il workflow usa un
fallback basato sul titolo; per accessibilità è preferibile inviare sempre una
didascalia che descriva ciò che si vede davvero.

## Policy e confini di fiducia

- Il gate `EX_BLOG_ADMIN_TELEGRAM_ID` precede Beam, Spectre, download, log e
  chiamate OpenRouter.
- Beam marca la sorgente autenticata; `ExBlog.Telegram.Image` rifiuta input che
  non provengono dal mount Telegram autenticato.
- Categoria e titolo generati sono valori, non comandi: vengono normalizzati a
  una sola riga e limitati rispettivamente a 80 e 160 caratteri.
- Il JSON SEO viene validato e limitato prima del Writer.
- I path copertina scritti dall’agente devono essere HTTPS o root-relative e
  non possono contenere traversal o backslash.
- Ogni mutazione Git resta protetta dalla policy Spectre; il modello non può
  auto-approvarla.
- Budget e costo vengono autorizzati prima di ogni richiesta OpenRouter.

## Dove estendere il showcase

Per aggiungere un nuovo campo editoriale:

1. aggiungere un leaf flow e il suo label terminale;
2. creare il prompt conversazionale HEEx della skill;
3. se serve AI, creare un renderer HEEx bounded e un helper read-only;
4. aggiungere il parametro tipizzato all’azione `@al` solo se deve raggiungere
   l’effetto finale;
5. coprire transizione, persistenza, AL estratta e policy con test separati.

Per una nuova mutazione, dichiarare `requires_action`, registrarla nel provider,
proteggerla con una policy e lasciare la scrittura in un boundary di dominio.
Non basta aggiungere un comando al prompt: in Spectre il prompt propone, il
runtime decide.

## Verifica browser

Spectre Lens è deliberatamente limitato al blog pubblico: articolo, indice,
metadati, link, immagini, sitemap e warning/errori del documento. Non viene
usato per il QR o per guidare la sessione Telegram dell’admin. Lightpanda
verifica DOM e semantica; per pixel, CSS e breakpoint serve un backend Remote
CDP con rendering grafico.
