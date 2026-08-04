# ExBlog

ExBlog is a Phoenix blog controlled by a single administrator through Telegram
and MCP. Canonical content lives as Markdown files in a GitHub repository;
Phoenix indexes it in ETS and serves it without SQL queries on the read path.
Spectre orchestrates the conversation, Prism selects the model tier, Kinetic
validates `@al` actions, and DETS stores local operational state without a SQL
database.

## What is included

- deterministic boot and configuration entirely through environment variables;
- Git clone, fetch, rebase, and push with an ephemeral token through
  `GIT_ASKPASS`;
- CommonMark parsing with `MDEx`, front matter with `YamlElixir`, and sanitized
  HTML;
- atomically replaced ETS index and periodic Git synchronization;
- multilingual blog content, tags, categories, translations, RSS, Atom,
  sitemap, and JSON-LD;
- a Spectre agent organized into reader, editorial, and operations skills,
  with HEEx prompts and Kinetic-planned `@al` actions;
- English as the operational language for the agent and every prompt, while
  article bodies, SEO metadata, and translations use the language selected for
  each article;
- a DETS-persisted Spectre semantic cache backed by OpenRouter embeddings,
  with automatic review only above a very high similarity threshold and no
  shortcut around mutation confirmations;
- guided article creation through nested flows for the brief, language,
  category, title, and SEO, with field-by-field OpenRouter generation and
  explicit confirmation before Git is changed;
- cover photos received from the administrator through `ex_gram`, validated,
  stored in `priv/static/images/articles`, and linked from Markdown front
  matter;
- on-demand verification of rendered pages with Spectre Lens and Lightpanda;
- a token ledger and spending limits in euros;
- an Argon2 password-protected web administrator area for connecting Telegram;
- a numeric Telegram ID gate before prompts, logs, and model calls;
- MCP Streamable HTTP with OAuth 2.1 for ChatGPT and the same tools exposed by
  the agent.

The [content contract](docs/content-contract.md) documents the directory
structure and front matter. The [architecture decisions](docs/architecture.md)
describe boot, data ownership, and security boundaries. The
[Spectre showcase walkthrough](docs/spectre-editorial-showcase.md) explains
nested flows, skills, HEEx prompts, Kinetic `@al`, policies, and Telegram
photos.

## Requirements

- Elixir 1.19 or later and a compatible OTP release;
- Git;
- a Spectre Lens-compatible Lightpanda binary, installed automatically in the
  Docker image;
- a dedicated GitHub content repository;
- Telegram API credentials and a Telegram account;
- an OpenRouter API key.

## Configuration

Copy the example, then replace every placeholder:

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

In development, `SECRET_KEY_BASE` can use the value already present in the
configuration. Generate a production value with `mix phx.gen.secret`.

Required application variables:

| Variable | Purpose |
| --- | --- |
| `EX_BLOG_ADMIN_PASSWORD_HASH` | Argon2 hash for the web administrator area |
| `EX_BLOG_ADMIN_TELEGRAM_ID` | sole authorized administrator identity |
| `EX_BLOG_TELEGRAM_API_ID` | Telegram application API ID |
| `EX_BLOG_TELEGRAM_API_HASH` | Telegram application API hash |
| `EX_BLOG_GITHUB_TOKEN` | access limited to the content repository |
| `EX_BLOG_GITHUB_REPOSITORY` | repository in `owner/name` format |
| `EX_BLOG_GITHUB_BRANCH` | canonical branch |
| `OPENROUTER_API_KEY` | LLM provider credential |
| `EX_BLOG_LLM_FAST_MODEL` | routing and short transformations |
| `EX_BLOG_LLM_BALANCED_MODEL` | SEO, summaries, and normal revisions |
| `EX_BLOG_LLM_DEEP_MODEL` | articles, translations, and complex revisions |
| `EX_BLOG_CLASSIFIER_MODEL` | Spectre router fallback |
| `EX_BLOG_MCP_TOKEN` | operator bearer for direct MCP clients, separate from OAuth |

By default, the semantic cache uses the same contract as `freelance`:
`EX_BLOG_EMBEDDING_MODEL=openrouter:perplexity/pplx-embed-v1-0.6b` and
`EX_BLOG_EMBEDDING_DIMENSIONS=1024`. Both settings are optional and may be
overridden, but the model, dimensions, and existing snapshots must remain
compatible.

`LIGHTPANDA_PATH` is optional when the binary is not available in `PATH` or at
`~/.local/bin/lightpanda`. Spectre Lens uses a public network policy for URLs
selected by the agent and rejects loopback addresses, private networks,
credentials embedded in URLs, and non-standard ports.

`EX_BLOG_CHATGPT_PUBLIC_BASE_URL` is optional and is needed only when the public
OAuth origin differs from `https://<PHX_HOST>`, for example when using a local
HTTPS tunnel. It must contain the origin without the `/mcp` path.

Production also requires `PHX_HOST` and `SECRET_KEY_BASE`. Optional variables
and defaults are listed in [.env.example](.env.example). If one or more required
values are missing or invalid, ExBlog reports every problem and exits before
starting the blog in a partial state.

## Startup

The boot process follows this order:

```text
ENV → validation → data directory → DETS storage → semantic cache
    → Git repository
    → image restoration → Markdown parsing → ETS index
    → Spectre/Prism/Kinetic → Telegram
    → web/MCP endpoint
```

The default data directory is `/data`; locally,
`EX_BLOG_DATA_DIR="$PWD/data"` is recommended because the path must be absolute.
The checkout lives in `data/repo`, and operational state lives in
`data/runtime.dets`.

## Public surfaces

| URL | Function |
| --- | --- |
| `/` and `/:lang` | published article index |
| `/:lang/:slug` | article page |
| `/tag/:tag` | tag filter; accepts `?lang=it` |
| `/category/:category` | category filter |
| `/feed.xml`, `/atom.xml` | RSS and Atom feeds |
| `/sitemap.xml`, `/robots.txt` | crawler discovery |
| `/health` | secret-free health check |
| `/mcp` | MCP endpoint with OAuth 2.1 |
| `/.well-known/*`, `/oauth/*` | ChatGPT OAuth discovery and protocol routes |

Public pages use an ETag derived from the indexed commit. Drafts are never
available through public routes, feeds, or the sitemap.

## Administrator area

Generate the password hash locally:

```bash
mix ex_blog.admin.hash_password 'a-long-password'
```

Set the output as `EX_BLOG_ADMIN_PASSWORD_HASH`, then open `/admin/login`.
After signing in, `/admin/telegram` shows the TDLib session status and guides
the connection through a QR code, phone number, verification code, and an
optional Telegram 2FA password.

The web session is encrypted, lasts no more than eight hours, and is also
invalidated before expiry when the configured password hash changes.
Administrator routes send `no-store` headers, cannot be indexed, and rate-limit
login attempts.

`EX_BLOG_TELEGRAM_SESSION_ID` is optional and defaults to `ex_blog`. The
persistent TDLib database is stored at
`$EX_BLOG_DATA_DIR/telegram/$EX_BLOG_TELEGRAM_SESSION_ID`.

## Telegram

The transport uses the TDLib client
[`elchemista/ex_gram`](https://github.com/elchemista/ex_gram), and therefore a
real Telegram account rather than the Bot API. Connect the account from the
protected `/admin/telegram` page; later boots reuse the persistent TDLib
database on the volume.

Only a sender whose ID matches `EX_BLOG_ADMIN_TELEGRAM_ID` reaches Beam,
Spectre, or OpenRouter. Other updates are ignored without logging their text.
The main deterministic commands are `/config`, `/budget`, `/sync`, `/articles`,
and `/check [URL]`; sensitive editorial operations require confirmation. The
agent replies in English. `/create` starts the editorial flow: after the brief,
use `generate category`, `generate title`, `generate SEO`, or `skip`. Select the
article language by code or English name, for example `en`, `English`, `it`, or
`Italian`, without invoking the LLM classifier. During the flow, a photo with a
caption becomes the draft cover. The image is downloaded only after the
administrator gate, stored under `priv/static/images/articles`, and replicated
to `$EX_BLOG_DATA_DIR/assets/images/articles` so it survives deployments.

When the URL is omitted, `/check` uses the canonical blog URL. It opens the page
with Spectre Lens, runs baseline technical checks, and asks the balanced model
for an assessment based only on observed content. Lightpanda verifies the DOM,
semantics, and metadata but not pixel-level rendering; the report states this
limit explicitly.

The Telegram username is informational only and is never used as identity.

## MCP

To connect ChatGPT, create a custom MCP app with only these settings:

- URL: `https://<PHX_HOST>/mcp`;
- transport: Streamable HTTP, protocol `2025-11-25`.

ChatGPT reads the `/.well-known/` documents, registers a public client, opens
`/oauth/authorize`, and starts an authorization code flow with PKCE S256. If the
administrator session is not already active, ExBlog stores the OAuth request in
the encrypted session, shows `/admin/login`, and returns automatically to the
consent screen after authentication. The scopes are `articles:read` and
`articles:write`; refresh uses `offline_access`.

The access token lasts 15 minutes, and the refresh token lasts 30 days. Every
refresh rotates the pair and revokes the previous pair. Plaintext values are
delivered to ChatGPT only once; `$EX_BLOG_DATA_DIR/runtime.dets` stores only
SHA-256 hashes, expiry times, scopes, and revocations. Nothing is written to the
Git repository. With the Fly volume mounted, the connection survives
deployments; a new login is needed only if the volume is lost, deleted, or
replaced.

`EX_BLOG_MCP_TOKEN` remains a separate administrator bearer for direct MCP
clients and operational scripts. Do not configure it inside ChatGPT.

`tools/list` exposes reading, page verification, generation, and editorial
management tools with `readOnlyHint`, `destructiveHint`, `idempotentHint`, and
`openWorldHint` annotations. `show_config` returns only a safe projection. Tool
errors are deliberately normalized so headers, tokens, and infrastructure
details are not propagated.

## Budget

`EX_BLOG_MONTHLY_BUDGET_EUR` limits monthly spending, while
`EX_BLOG_MAX_ARTICLE_COST_EUR` limits one editorial operation. When a request
would exceed a limit, new balanced/deep generations are blocked before the HTTP
request. Reading, rendering, deterministic audits, synchronization, and
channels remain available.

The accounting USD/EUR rate is configured with `EX_BLOG_USD_EUR_RATE`; it is
not a real-time currency exchange service.

## Tests and quality

```bash
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test
mix precommit
```

Credo uses the repository's strict configuration. Dialyzer also checks ignored
return values and error paths. `mix precommit` compiles with warnings treated as
errors, removes unused lock entries, formats the project, runs both static
checks, and starts the complete test suite.

## Deploying to Fly.io

1. Change `app` and `PHX_HOST` in [fly.toml](fly.toml).
2. Create the app and volume in the same region:

   ```bash
   fly apps create your-ex-blog-name
   fly volumes create ex_blog_data --region fra --size 1
   ```

3. Set the secrets:

   ```bash
   EX_BLOG_DEPLOY_ADMIN_HASH="$(mix ex_blog.admin.hash_password 'a-long-password')"

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
     EX_BLOG_EMBEDDING_MODEL="openrouter:perplexity/pplx-embed-v1-0.6b" \
     EX_BLOG_EMBEDDING_DIMENSIONS="1024" \
     EX_BLOG_MCP_TOKEN="$(openssl rand -hex 32)"
   ```

4. Run `fly deploy`.

Do not configure a `release_command`: DETS storage and the checkout are opened
directly on the machine that owns the volume. The configuration keeps exactly
one active machine (`min_machines_running = 1`) because DETS and the checkout
are local to that volume; GitHub remains the durable source of content. The
same volume stores OAuth hashes, so a normal deployment does not disconnect
ChatGPT.

To change credentials, repository, models, or administrator, update the
environment variables or Fly Secrets and restart. The agent can explain which
variable to change, but it cannot read or rotate those values.
