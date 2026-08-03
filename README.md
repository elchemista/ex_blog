# ExBlog

ExBlog è un blog Phoenix controllato da un unico amministratore via Telegram e
MCP. I contenuti canonici sono file Markdown in una repository GitHub; Phoenix
li indicizza in ETS e li pubblica senza interrogazioni SQL nel percorso di
lettura. Spectre orchestra la conversazione, Prism sceglie il livello del
modello, Kinetic valida le azioni `@al` e DETS conserva lo stato operativo
locale senza un database SQL.

## Cosa è incluso

- boot deterministico e configurazione interamente da ENV;
- clone, fetch, rebase e push Git con token effimero tramite `GIT_ASKPASS`;
- parsing CommonMark con `MDEx`, front matter con `YamlElixir` e HTML sanificato;
- indice ETS sostituito atomicamente e sync Git periodico;
- blog multilingua, tag, categorie, traduzioni, RSS, Atom, sitemap e JSON-LD;
- agente Spectre organizzato in skill di lettura, editoriale e operazioni, con
  prompt HEEx e azioni `@al` pianificate da Kinetic;
- creazione articolo guidata da flow annidati per titolo, categoria, lingua e
  brief, seguita da conferma esplicita prima di modificare Git;
- verifica on demand delle pagine renderizzate con Spectre Lens e Lightpanda;
- ledger dei token e limiti di spesa in euro;
- area web amministratore protetta da password Argon2 per associare Telegram;
- gate Telegram sull’ID numerico prima di prompt, log e chiamate al modello;
- MCP Streamable HTTP autenticato con gli stessi strumenti dell’agente.

Il [contratto dei contenuti](docs/content-contract.md) documenta struttura e
front matter. Le [decisioni architetturali](docs/architecture.md) descrivono
boot, dati e confini di sicurezza.

## Requisiti

- Elixir 1.19 o successivo e OTP compatibile;
- Git;
- Lightpanda compatibile con Spectre Lens (installato automaticamente
  nell'immagine Docker);
- una repository GitHub dedicata ai contenuti;
- credenziali Telegram API e un account Telegram;
- una chiave OpenRouter.

## Configurazione

Copia l’esempio e sostituisci tutti i placeholder:

```bash
cp .env.example .env
set -a
. ./.env
set +a
mix setup
mix spectre.lens.install --channel nightly --out ~/.local/bin --force
mix spectre.lens.doctor
mix phx.server
```

In sviluppo `SECRET_KEY_BASE` può essere quello già presente nella config. In
produzione generane uno con `mix phx.gen.secret`.

Variabili obbligatorie dell’applicazione:

| Variabile | Scopo |
| --- | --- |
| `EX_BLOG_ADMIN_PASSWORD_HASH` | hash Argon2 per l’area amministratore web |
| `EX_BLOG_ADMIN_TELEGRAM_ID` | unica identità amministrativa autorizzata |
| `EX_BLOG_TELEGRAM_API_ID` | API ID dell'applicazione Telegram |
| `EX_BLOG_TELEGRAM_API_HASH` | API hash dell'applicazione Telegram |
| `EX_BLOG_GITHUB_TOKEN` | accesso limitato alla repository dei contenuti |
| `EX_BLOG_GITHUB_REPOSITORY` | repository nel formato `owner/name` |
| `EX_BLOG_GITHUB_BRANCH` | branch canonico |
| `OPENROUTER_API_KEY` | provider LLM |
| `EX_BLOG_LLM_FAST_MODEL` | routing e trasformazioni brevi |
| `EX_BLOG_LLM_BALANCED_MODEL` | SEO, sintesi e revisioni normali |
| `EX_BLOG_LLM_DEEP_MODEL` | articoli, traduzioni e revisioni complesse |
| `EX_BLOG_CLASSIFIER_MODEL` | fallback del router Spectre |
| `EX_BLOG_MCP_TOKEN` | bearer token dell'endpoint MCP |

`LIGHTPANDA_PATH` è opzionale quando il binario non è nel `PATH` o in
`~/.local/bin/lightpanda`. Spectre Lens usa una policy di rete pubblica per le
URL scelte dall’agente e rifiuta loopback, reti private, credenziali nella URL e
porte non standard.

In produzione sono obbligatorie anche `PHX_HOST` e `SECRET_KEY_BASE`. Le
variabili opzionali e i default sono elencati in [.env.example](.env.example).
Se uno o più valori obbligatori mancano o sono invalidi, ExBlog elenca tutti i
problemi e termina prima di avviare il blog in uno stato parziale.

## Avvio

Il processo di boot segue quest’ordine:

```text
ENV → validazione → directory dati → storage DETS → repository Git
    → parsing Markdown → indice ETS → Spectre/Prism/Kinetic → Telegram
    → endpoint web/MCP
```

La directory dati predefinita è `/data`; in locale è consigliato
`EX_BLOG_DATA_DIR="$PWD/data"` perché il path deve essere assoluto. Il checkout
vive in `data/repo` e lo stato operativo in `data/runtime.dets`.

## Superfici pubbliche

| URL | Funzione |
| --- | --- |
| `/` e `/:lang` | indice degli articoli pubblicati |
| `/:lang/:slug` | articolo |
| `/tag/:tag` | filtro per tag; accetta `?lang=it` |
| `/category/:category` | filtro per categoria |
| `/feed.xml`, `/atom.xml` | feed RSS e Atom |
| `/sitemap.xml`, `/robots.txt` | discovery crawler |
| `/health` | health check senza segreti |
| `/mcp` | endpoint MCP autenticato |

Le pagine pubbliche usano un ETag derivato dal commit indicizzato. Le bozze non
sono mai leggibili dalle route pubbliche, dai feed o dalla sitemap.

## Area amministratore

Genera localmente l’hash della password:

```bash
mix ex_blog.admin.hash_password 'una-password-lunga'
```

Configura l’output come `EX_BLOG_ADMIN_PASSWORD_HASH`, quindi apri
`/admin/login`. Dopo l’accesso, `/admin/telegram` mostra lo stato della sessione
TDLib e guida l’associazione tramite QR, numero telefonico, codice ed eventuale
password Telegram 2FA.

La sessione web è cifrata, dura al massimo otto ore e viene invalidata anche
prima della scadenza quando cambia l’hash configurato. Le route amministrative
inviano header `no-store`, non sono indicizzabili e applicano un limite ai
tentativi di login.

`EX_BLOG_TELEGRAM_SESSION_ID` è opzionale e vale `ex_blog` per default. Il
database TDLib persistente viene salvato in
`$EX_BLOG_DATA_DIR/telegram/$EX_BLOG_TELEGRAM_SESSION_ID`.

## Telegram

Il trasporto usa il client TDLib
[`elchemista/ex_gram`](https://github.com/elchemista/ex_gram) e quindi un account
Telegram reale, non la Bot API. L’associazione si esegue dalla pagina
protetta `/admin/telegram`; gli avvii successivi riutilizzano il database TDLib
persistente sul volume.

Solo il mittente il cui ID coincide con `EX_BLOG_ADMIN_TELEGRAM_ID` raggiunge
Beam, Spectre o OpenRouter. Gli altri update sono ignorati senza registrarne il
testo. I comandi deterministici principali sono `/config`, `/budget`, `/sync`,
`/articles` e `/check [URL]`; le operazioni editoriali sensibili richiedono
conferma. `/check` usa la URL canonica del blog quando la URL è omessa, apre la
pagina con Spectre Lens, esegue controlli tecnici di base e chiede al modello
balanced una valutazione basata esclusivamente sul contenuto osservato.
Lightpanda verifica DOM, semantica e metadati ma non il rendering pixel-level;
il report dichiara esplicitamente questo limite.

Lo username è puramente informativo: non viene usato come identità.

## MCP

Configura il client con:

- URL: `https://<PHX_HOST>/mcp`;
- header: `Authorization: Bearer <EX_BLOG_MCP_TOKEN>`;
- trasporto: Streamable HTTP, protocollo `2025-11-25`.

`tools/list` espone strumenti di lettura, verifica pagine, generazione e
gestione editoriale con annotazioni `readOnlyHint`, `destructiveHint`,
`idempotentHint` e `openWorldHint`. `show_config` restituisce solo una
proiezione sicura. Errori degli strumenti sono deliberatamente normalizzati per
non propagare header, token o dettagli infrastrutturali.

## Budget

`EX_BLOG_MONTHLY_BUDGET_EUR` limita la spesa mensile e
`EX_BLOG_MAX_ARTICLE_COST_EUR` limita una singola operazione editoriale. Quando
un limite sarebbe superato, le nuove generazioni balanced/deep vengono
bloccate prima della richiesta HTTP. Lettura, rendering, audit deterministici,
sync e canali restano disponibili.

Il cambio USD/EUR contabile è configurabile con `EX_BLOG_USD_EUR_RATE`; non è
un servizio di cambio in tempo reale.

## Test e qualità

```bash
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test
mix precommit
```

Credo usa la configurazione strict del repository. Dialyzer controlla anche i
return non consumati e i percorsi di errore. `mix precommit` compila con warning
trattati come errori, rimuove lock non più usati, formatta, esegue entrambi i
controlli statici e avvia l’intera suite.

## Deploy su Fly.io

1. Cambia `app` e `PHX_HOST` in [fly.toml](fly.toml).
2. Crea app e volume nella stessa regione:

   ```bash
   fly apps create nome-ex-blog
   fly volumes create ex_blog_data --region fra --size 1
   ```

3. Imposta i segreti:

   ```bash
   EX_BLOG_DEPLOY_ADMIN_HASH="$(mix ex_blog.admin.hash_password 'una-password-lunga')"

   fly secrets set \
     SECRET_KEY_BASE="$(mix phx.gen.secret)" \
     EX_BLOG_ADMIN_PASSWORD_HASH="$EX_BLOG_DEPLOY_ADMIN_HASH" \
     EX_BLOG_ADMIN_TELEGRAM_ID="123456789" \
     EX_BLOG_TELEGRAM_API_ID="12345" \
     EX_BLOG_TELEGRAM_API_HASH="..." \
     EX_BLOG_GITHUB_TOKEN="github_pat_..." \
     EX_BLOG_GITHUB_REPOSITORY="elchemista/elchemista-blog" \
     OPENROUTER_API_KEY="sk-or-..." \
     EX_BLOG_LLM_FAST_MODEL="openai/gpt-5.6-luna" \
     EX_BLOG_LLM_BALANCED_MODEL="openai/gpt-5.6-terra" \
     EX_BLOG_LLM_DEEP_MODEL="openai/gpt-5.6-sol" \
     EX_BLOG_CLASSIFIER_MODEL="openai/gpt-5.6-luna" \
     EX_BLOG_MCP_TOKEN="$(openssl rand -hex 32)"
   ```

4. Esegui `fly deploy`.

Non va configurato un `release_command`: lo storage DETS e il checkout vengono
aperti direttamente sulla macchina che possiede il volume. La configurazione
mantiene una sola macchina attiva (`min_machines_running = 1`) perché DETS e il
checkout sono locali al volume; GitHub resta la sorgente durevole dei contenuti.

Per cambiare credenziali, repository, modelli o amministratore, aggiorna ENV o
Fly Secrets e riavvia. L’agente può spiegare quale variabile modificare, ma non
può leggere o ruotare quei valori.
