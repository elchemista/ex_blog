# ExBlog

> A Git-native editorial agent built with Phoenix and the Spectre ecosystem.

ExBlog is a working showcase of an agent that does more than answer questions.
An administrator can talk to it through Telegram or MCP, enter a guided
editorial workflow, generate multilingual content with OpenRouter, approve a
repository mutation, and publish a real Markdown article. GitHub remains the
canonical content store; Phoenix serves a fast ETS projection without a SQL
database.

The project brings the Spectre stack together in one deliberately visible
workflow:

- **Spectre Agent** owns routing, conversational state, memory, and execution;
- **Spectre Skills** separate reading, editorial work, and operations;
- **Spectre Kinetic** turns model output into validated `@al` actions;
- **Spectre Prism** selects fast, balanced, or deep OpenRouter models by purpose;
- **Spectre Beam** normalizes Telegram text and images through ExGram;
- **Spectre Lens** audits rendered public blog pages from inside the agent;
- **HEEx prompt templates** keep prompts reviewable and next to their skill;
- **semantic routing** learns only safe read intents and persists them in DETS.

The agent operates in English. Articles, metadata, and translations can use any
language enabled in `EX_BLOG_SUPPORTED_LANGUAGES`.

## The showcase in one diagram

```mermaid
flowchart LR
    Admin[Authorized administrator] --> Telegram[Telegram]
    Telegram --> ExGram[ExGram + TDLib session]
    ExGram --> Beam[Spectre Beam]
    ChatGPT[ChatGPT or MCP client] --> MCP[OAuth 2.1 / MCP]
    Beam --> Agent[Spectre Agent]
    MCP --> Agent
    Agent --> Skills[Reader · Editorial · Operations skills]
    Skills --> Router[Regex · active flow · semantic cache · classifier]
    Skills --> Kinetic[Spectre Kinetic @al validation]
    Skills --> Prism[Spectre Prism model routing]
    Skills --> Lens[Spectre Lens public-page audit]
    Kinetic --> Policy[Confirmation policy]
    Policy --> Writer[Markdown writer]
    Writer --> GitHub[(GitHub content repository)]
    GitHub --> Index[ETS content index]
    Index --> Phoenix[Phoenix blog, feeds, and sitemap]
    Prism --> OpenRouter[OpenRouter]
    Agent --> DETS[(DETS operational state)]
```

There are four different persistence responsibilities:

| Store | Responsibility |
| --- | --- |
| GitHub repository | canonical Markdown content and its history |
| ETS | replaceable, in-memory read projection for the public blog |
| `$EX_BLOG_DATA_DIR/runtime.dets` | agent state, semantic examples, budget ledger, OAuth token hashes, and operational records |
| `$EX_BLOG_DATA_DIR/telegram/<session>` | persistent TDLib authorization database |

Article images are content-addressed on the data volume and restored into
`priv/static/images/articles` at boot.

## Why Spectre is useful here

This application treats an agent as a typed workflow, not as an unrestricted
chat completion.

### Skills and nested flows

[`ExBlog.Agent`](lib/ex_blog/agent.ex) installs three focused skills:

| Skill | Scope |
| --- | --- |
| `reader` | list, read, search, and audit public blog pages |
| `editorial` | create, revise, translate, optimize, publish, unpublish, and delete |
| `operations` | safe configuration, provider health, budget, and Git synchronization |

The `/create` conversation is implemented as nested Spectre flows:

```text
article_creation
├── article_brief
├── article_language
├── article_category
├── article_title
└── article_seo
```

`Spectre.State.current_flow` is the cursor. A free-text answer is therefore
interpreted as the field currently being requested instead of being sent back
through a generic classifier. `/cancel` and authenticated Telegram images are
global interrupts, so they remain available at every step.

The implementation is in
[`editorial.ex`](lib/ex_blog/agent/skills/editorial.ex).

### HEEx prompts

Agent copy and model instructions are HEEx templates under
[`lib/ex_blog_web/prompts`](lib/ex_blog_web/prompts). The agent has one prompt
root, while each skill can declare its own nested root. This keeps prose out of
the workflow module, supports small prompt-specific assigns, and makes every
prompt independently reviewable.

Renderer templates for article generation, revision, translation, SEO, title,
category, and classification are separate from conversational prompts. Values
inserted into them are bounded, escaped, and stripped of configured secrets.

### Kinetic Action Language

The model is not allowed to call arbitrary Elixir functions. Kinetic exposes a
typed catalog from
[`kinetic_actions.ex`](lib/ex_blog/agent/kinetic_actions.ex), validates the
generated Action Language against the declared `@al` signatures, and only then
hands the action back to Spectre.

Examples of canonical AL:

```text
LIST ARTICLES
READ ARTICLE LANG="en" SLUG="spectre-agents"
SEARCH ARTICLES QUERY="Telegram editorial workflow"
CHECK BLOG PAGE URL="https://blog.example.com/en/spectre-agents"
CREATE ARTICLE TITLE="Building a Spectre agent" LANG="en" CATEGORY="Engineering" BRIEF="Explain the architecture" GENERATE_SEO=true COVER="" COVER_ALT=""
REVISE ARTICLE LANG="en" SLUG="spectre-agents" INSTRUCTIONS="Add a deployment section"
TRANSLATE ARTICLE LANG="en" SLUG="spectre-agents" TARGET_LANG="it"
GENERATE ARTICLE SEO LANG="en" SLUG="spectre-agents"
PUBLISH ARTICLE LANG="en" SLUG="spectre-agents"
UNPUBLISH ARTICLE LANG="en" SLUG="spectre-agents"
DELETE ARTICLE LANG="en" SLUG="spectre-agents"
SYNC BLOG REPOSITORY
```

The administrator normally sends the shorter commands described below.
Kinetic AL is the validated internal contract between planning and execution.

### Policies before side effects

Create, revise, translate, generate SEO, publish, unpublish, delete, and
repository synchronization are protected Spectre actions. The agent stages the
effect and accepts only `yes` or `confirm`; `no` or `cancel` rejects it. Three
invalid confirmation attempts cancel the operation.

Read actions never mutate Git. Semantic learning is also restricted to
explicitly learnable read routes, so a learned match can never approve a write.

### Prism model routing

Prism selects a model tier by purpose:

| Tier | Typical work |
| --- | --- |
| fast | fallback classification and category generation |
| balanced | title generation, SEO, normal revisions, and page assessment |
| deep | complete articles, translations, and complex editorial work |

Budget checks happen before balanced or deep requests. Model identifiers remain
runtime configuration, so changing providers or models does not alter the
skills.

### Deterministic routing plus semantic reuse

The routing order is:

```text
English regex → active nested-flow continuation → exact semantic cache
→ vector semantic search → arbitration → LLM classifier fallback
```

The default semantic threshold is `0.94`. An unreviewed learned read intent can
become verified automatically only at `0.985` similarity with at least a
`0.05` margin over the next label. Embeddings and learned rows are persisted in
DETS. Editorial mutations have `learn: false` and still require policy
confirmation.

## A complete editorial conversation

The shortest way to understand the project is to run `/create` in Telegram:

```text
Administrator: /create
Agent: Describe the topic, goal, audience, important points, and tone.

Administrator: Explain how typed agent actions make Git publishing safer.
Agent: Which language should I use?

Administrator: en
Agent: Choose a category, create one, or reply `generate category`.

Administrator: generate category
Agent: Enter a title or reply `generate title`.

Administrator: generate title
Agent: Reply `generate SEO` or `skip`.

Administrator: [sends a cover photo with an accessible caption]
Agent: The image is attached. Continue with the current step.

Administrator: generate SEO
Agent: Shows the complete intake and asks for confirmation.

Administrator: yes
Agent: Generates the article, writes one Markdown file, commits, rebases,
       pushes, rebuilds ETS, and returns the new draft.
```

Publishing is a separate protected action:

```text
Administrator: /publish en typed-agent-actions
Agent: Asks for confirmation.
Administrator: yes
Agent: Updates the Markdown status, commits, pushes, and refreshes the index.
```

The photo can be sent at any point while the article-creation flow is active.
`/cancel` exits the flow without creating an article.

## Agent command reference

Commands and natural-language requests are English-first. The examples below
are the predictable operator shortcuts; equivalent English requests can be
routed through the same skills.

### Reading and diagnostics

| Command | Result | Side effect |
| --- | --- | --- |
| `/articles [language]` | list article summaries, including drafts for the administrator | none |
| `/read <language> <slug>` | return one complete article | none |
| `/search <query>` | search title, category, tags, and Markdown body | none |
| `/check [https://public-url]` | audit the canonical blog URL or the supplied public page with Spectre Lens | browser read plus optional balanced-model assessment |
| `/config` | show a redacted, safe runtime configuration | none |
| `/budget` | show daily and monthly AI accounting | none |
| `check OpenRouter status` | check provider reachability and configured model availability | external read |
| `/sync` | fetch the canonical branch and rebuild ETS | protected Git write operation |

Article identifiers use a supported language followed by a slug, for example
`/read en spectre-agents`.

### Editorial work

| Command | Result | Model / confirmation |
| --- | --- | --- |
| `/create` | start the brief → language → category → title → SEO flow | fast/balanced/deep as needed; confirmation before generation and Git |
| `/revise <lang> <slug> <instructions>` | prepare a Markdown revision; an exact approved body can then be applied | balanced by default; protected |
| `/translate <lang> <slug> to <target-lang>` | create a translated draft linked to its source | deep; protected |
| `/seo <lang> <slug>` | generate SEO title, description, tags, and optional alt text | balanced; protected |
| `/publish <lang> <slug>` | change a draft to `published` | protected |
| `/unpublish <lang> <slug>` | return a published article to `draft` | protected |
| `/delete <lang> <slug>` | remove the Markdown file | destructive and protected |
| `/cancel` | leave article creation or reject a pending confirmation | no side effect |

## Prepare the content repository

Use a dedicated GitHub repository for content. It may be private. ExBlog owns
its runtime checkout, so do not manually edit
`$EX_BLOG_DATA_DIR/repo`; periodic synchronization deliberately resets that
checkout to the configured remote branch.

1. Create the repository and its canonical branch.
2. Add an initial commit. A completely empty remote has no branch for
   `git clone --branch`, so a README or `.gitkeep` commit is sufficient.
3. Create the language directories under the configured content root.
4. Create a repository-scoped credential that can clone and push. A
   fine-grained GitHub token limited to this repository with repository
   **Contents: read and write** is the intended setup.
5. Put `owner/repository`, branch, token, and commit author identity in the
   ExBlog environment.

One possible initial repository is:

```text
content/
├── en/
│   └── .gitkeep
└── it/
    └── .gitkeep
```

`EX_BLOG_CONTENT_ROOT` defaults to `content`, and every directory code must
also appear in `EX_BLOG_SUPPORTED_LANGUAGES`.

### Markdown contract

Agent-created files use `content/<lang>/YYYY-MM-DD-<slug>.md`:

```markdown
---
title: "Building a Spectre editorial agent"
slug: "building-a-spectre-editorial-agent"
lang: "en"
status: "draft"
date: "2026-08-04"
updated: "2026-08-04"
category: "Engineering"
tags: ["elixir", "phoenix", "spectre"]
seo_title: "Build a Git-native Spectre editorial agent"
seo_description: "A practical architecture for typed editorial workflows, Telegram, and Git."
cover: "/images/articles/<sha256>.webp"
cover_alt: "Diagram of the editorial agent workflow"
translation_of: null
---

## Introduction

The article body uses CommonMark.
```

`status` is either `draft` or `published`. Only published articles reach public
routes, feeds, and the sitemap. Invalid Markdown entries are recorded by the
index audit and skipped instead of taking down the entire blog.

See the complete [content contract](docs/content-contract.md) for validation,
translations, rendering, and image rules.

### What happens on every Git mutation

```text
validate fields and safe path
→ write or remove exactly one Markdown file
→ git add -- <that path>
→ commit as the configured author
→ fetch the configured branch
→ rebase on origin/<branch>
→ push HEAD:<branch>
→ rebuild the complete ETS index
→ read the resulting article back
```

Commit messages are deterministic: `Create <lang>/<slug>`,
`Update <lang>/<slug>`, or `Delete <lang>/<slug>`. ExBlog never embeds the
GitHub token in the remote URL, command arguments, local Git configuration, or
logs; it supplies the credential through a short-lived `GIT_ASKPASS` process.
A rebase conflict aborts the push instead of force-pushing over remote work.

At boot, ExBlog clones the selected branch when no checkout exists. When a
checkout already exists, it fetches and resets it to `origin/<branch>`. It then
parses Markdown and atomically builds the ETS index. The same sync runs every
`EX_BLOG_GIT_SYNC_INTERVAL_MS`.

## Configure the environment

Copy the complete template:

```bash
cp .env.example .env
```

Never commit `.env`. When sourcing it locally, quote the Argon2 hash because it
contains `$` characters:

```bash
set -a
. ./.env
set +a
```

ExBlog validates the complete configuration before starting. Missing or invalid
values are reported together, and the supervision tree does not start in a
partially configured state.

### Administrator and Telegram

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `EX_BLOG_ADMIN_PASSWORD_HASH` | yes | — | Argon2id hash accepted by `/admin/login`; generate it locally with the included Mix task |
| `EX_BLOG_ADMIN_TELEGRAM_ID` | yes | — | positive numeric Telegram user ID of the only allowed command sender |
| `EX_BLOG_ADMIN_TELEGRAM_USERNAME` | no | unset | informational label only; never used for authorization |
| `EX_BLOG_TELEGRAM_API_ID` | yes | — | positive Telegram application API ID |
| `EX_BLOG_TELEGRAM_API_HASH` | yes | — | Telegram application API hash; secret |
| `EX_BLOG_TELEGRAM_SESSION_ID` | no | `ex_blog` | TDLib session name; letters, numbers, `_`, and `-` only |

### Git content

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `EX_BLOG_GITHUB_TOKEN` | yes | — | repository-scoped credential with clone and push access |
| `EX_BLOG_GITHUB_REPOSITORY` | yes | — | canonical repository in `owner/name` form |
| `EX_BLOG_GITHUB_BRANCH` | yes | — | canonical branch, commonly `main` |
| `EX_BLOG_GITHUB_AUTHOR_NAME` | no | `ExBlog Agent` | author and committer name for agent changes |
| `EX_BLOG_GITHUB_AUTHOR_EMAIL` | no | `ex-blog@users.noreply.github.com` | author and committer email |
| `EX_BLOG_CONTENT_ROOT` | no | `content` | safe repository-relative directory containing language folders |
| `EX_BLOG_GIT_SYNC_INTERVAL_MS` | no | `900000` | periodic fetch/reset/index interval in milliseconds |

### OpenRouter, routing, and budget

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `OPENROUTER_API_KEY` | yes | — | OpenRouter credential used only by the provider boundary |
| `EX_BLOG_LLM_FAST_MODEL` | yes | — | classification and small generation model ID |
| `EX_BLOG_LLM_BALANCED_MODEL` | yes | — | title, SEO, normal revision, and page-audit model ID |
| `EX_BLOG_LLM_DEEP_MODEL` | yes | — | full article and translation model ID |
| `EX_BLOG_CLASSIFIER_MODEL` | yes | — | Spectre classifier fallback model ID; it may equal the fast model |
| `EX_BLOG_EMBEDDING_MODEL` | no | `openrouter:perplexity/pplx-embed-v1-0.6b` | embedding provider and model used by semantic routing |
| `EX_BLOG_EMBEDDING_DIMENSIONS` | no | `1024` | vector dimensions; must match the selected embedding model and persisted snapshots |
| `EX_BLOG_MONTHLY_BUDGET_EUR` | no | `20` | positive monthly AI spending ceiling |
| `EX_BLOG_MAX_ARTICLE_COST_EUR` | no | `2` | positive ceiling for one editorial operation |
| `EX_BLOG_USD_EUR_RATE` | no | `0.92` | fixed accounting conversion rate, not a live exchange-rate service |

### Languages, storage, web, and integrations

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `EX_BLOG_DEFAULT_LANGUAGE` | no | `it` | default two-letter language code; it must be supported |
| `EX_BLOG_SUPPORTED_LANGUAGES` | no | `it,en` | comma-separated language codes such as `it,en` or `en,pt-BR` |
| `EX_BLOG_DATA_DIR` | no | `/data` | absolute writable path for checkout, DETS, TDLib, and durable images |
| `EX_BLOG_MCP_TOKEN` | yes | — | separate bearer for direct operator MCP clients; ChatGPT OAuth does not use it |
| `EX_BLOG_CHATGPT_PUBLIC_BASE_URL` | no | `https://<PHX_HOST>` | public HTTPS origin for OAuth behind a tunnel or proxy; no path, query, or credentials |
| `LIGHTPANDA_PATH` | no | searched in `PATH` and `~/.local/bin` | explicit Lightpanda executable used by Spectre Lens |
| `PHX_HOST` | production | — | public hostname used by Phoenix, canonical metadata, feeds, sitemap, and OAuth |
| `SECRET_KEY_BASE` | production | — | signs and encrypts Phoenix sessions and related secrets |
| `PHX_SERVER` | release | unset | set to a non-empty value, normally `true`, to start the web endpoint in a release |
| `PORT` | no | `4000` | HTTP listen port |

Model names in [.env.example](.env.example) are examples. Replace them with
model IDs currently available to your OpenRouter account.

## Install and run locally

Requirements:

- Elixir 1.19 or later with a compatible OTP release;
- Git;
- a writable absolute data directory;
- a GitHub content repository and credential;
- an OpenRouter API key;
- a Telegram application and user account;
- the native `tdlib-json-cli` backend required by ExGram;
- Lightpanda only when using `/check`.

Install dependencies and the TDLib backend:

```bash
mix deps.get
mix ex_gram.setup_tdlib --install
mix setup
```

`--install` may use the system package manager and require `sudo`. If CMake,
Make, a C++ compiler, gperf, OpenSSL headers, zlib headers, and `pkg-config` are
already installed, use `mix ex_gram.setup_tdlib` without the flag. Building
TDLib is intentionally explicit and can take time.

Generate the administrator password hash locally:

```bash
mix ex_blog.admin.hash_password 'choose-at-least-12-characters'
```

Put the printed hash in `EX_BLOG_ADMIN_PASSWORD_HASH`, complete `.env`, source
it, and start Phoenix:

```bash
set -a
. ./.env
set +a
mix phx.server
```

For public-page audits, install and verify Lightpanda:

```bash
mix spectre.lens.install --channel nightly --out ~/.local/bin --force
mix spectre.lens.doctor
```

The local data path in `.env.example` uses
`EX_BLOG_DATA_DIR="${PWD}/data"` because the configured path must be absolute.

## Telegram through ExGram and Spectre Beam

This repository integrates
[`elchemista/ex_gram`](https://github.com/elchemista/ex_gram) from GitHub.
ExGram is a supervised TDLib client for **Telegram user accounts**, not a Bot
API client.

The channel is mounted in [`ExBlog.AI`](lib/ex_blog/ai.ex):

```elixir
install Spectre.Beam, delivery: :caller_owned do
  channel(:telegram,
    type: :telegram,
    adapter: Spectre.Beam.Adapters.ExGram,
    capabilities: [:text, :image],
    planner_exposure: :none,
    typing: true
  )
end
```

`ExBlog.Telegram.Transport` owns the ExGram session, subscribes to TDLib events,
publishes a secret-free connection projection to Phoenix PubSub, and sends
normalized inbound messages to `Spectre.Beam`. Beam converts provider-specific
updates into Spectre inputs; the gateway then applies the numeric administrator
gate before prompts, memory, logs, or OpenRouter can see the message.

Naming note: **ExWapp is not wired into ExBlog**. Spectre Beam can support other
adapters, including an ExWapp channel in a different application, but this
showcase mounts only `Spectre.Beam.Adapters.ExGram`. There are therefore no
ExWapp environment variables or WhatsApp pairing steps in this repository.

### Obtain Telegram API credentials

Create your own Telegram application through
[Telegram's official API application page](https://my.telegram.org/apps) and
copy its `api_id` and `api_hash` into `EX_BLOG_TELEGRAM_API_ID` and
`EX_BLOG_TELEGRAM_API_HASH`. These identify the application; they are not a bot
token and they do not authorize a user session by themselves.

Set `EX_BLOG_ADMIN_TELEGRAM_ID` to the numeric user ID that is allowed to send
commands. The optional username is only a display hint and changing a username
never changes authorization.

ExBlog ignores messages marked by Telegram as `from_me`. In practice, the
clearest topology is:

```text
personal administrator account
    -- sends commands -->
dedicated Telegram account connected to ExBlog through ExGram
```

The personal account's numeric ID is
`EX_BLOG_ADMIN_TELEGRAM_ID`; the dedicated account's phone number is the one
paired from `/admin/telegram`. If the same connected account sends its own
messages, TDLib marks them as outgoing and ExBlog intentionally ignores them.

### Protect the connection page

ExBlog does not generate a temporary boot token. It uses a stable password
whose Argon2id hash is supplied through the environment:

```bash
mix ex_blog.admin.hash_password 'choose-at-least-12-characters'
```

Only the hash reaches the server. `/admin/login` verifies the password with
Argon2 and establishes a signed, encrypted, HTTP-only, same-site session. The
session expires after eight hours, and changing
`EX_BLOG_ADMIN_PASSWORD_HASH` immediately invalidates existing sessions.
Login attempts are rate-limited.

Every administrator response uses `Cache-Control: no-store`, denies framing,
and sets `X-Robots-Tag: noindex, nofollow, noarchive`. Deploy the page only
behind HTTPS.

### Connect the Telegram number

1. Start ExBlog with the Telegram API variables and a persistent
   `EX_BLOG_DATA_DIR`.
2. Open `https://<PHX_HOST>/admin/login`.
3. Enter the plaintext password whose hash is configured in the environment.
4. Open the protected `/admin/telegram` LiveView.
5. Choose one authorization path:
   - **QR:** request a QR code, then use an already authorized Telegram client
     for the receiving account to open **Settings → Devices → Link Desktop
     Device** and scan it.
   - **Phone:** enter the receiving account number in international form, such
     as `+393331234567`, then submit the Telegram code and, when requested, its
     two-step-verification password.
6. Wait for the live status to become connected.

The QR login link is held only in memory. Authentication codes and the
two-step-verification password are forwarded to TDLib and are never persisted
or logged. The durable authorization database is:

```text
$EX_BLOG_DATA_DIR/telegram/$EX_BLOG_TELEGRAM_SESSION_ID
```

Keep that directory on a persistent volume. Normal restarts and deployments
then reuse the session without another QR scan. Losing the directory, changing
the session ID, or Telegram revoking the session requires a new login.

### Telegram cover images

While `/create` is active, the authorized administrator can send JPEG, PNG,
GIF, or WebP images up to 10 MB. ExBlog:

1. lets Beam authenticate and normalize the image update;
2. downloads bytes from ExGram only inside the active editorial flow;
3. detects the format from magic bytes rather than the Telegram filename;
4. stores the image under its SHA-256 digest;
5. uses the caption as accessible cover text;
6. adds only the public path to Markdown.

The public and durable copies are:

```text
priv/static/images/articles/<sha256>.<ext>
$EX_BLOG_DATA_DIR/assets/images/articles/<sha256>.<ext>
```

The durable copy is restored into the release's static tree at boot.

## Spectre Lens: public blog verification only

`/check` is a reader-skill action for inspecting a rendered **public blog or
article page**. It is not part of administrator login, QR pairing, or Telegram
connection testing.

For an audited page, Lens observes the document title, main content, semantic
tree, links, forms, interactive elements, structured data, and browser
warnings/errors. Deterministic checks cover the single `h1`, `lang`, viewport,
meta description, canonical URL, image alt text, Open Graph metadata, and
structured data. Before any projection enters a model prompt, ExBlog converts
it with `SpectreLens.agent_context/2` and marks page content as untrusted.

Agent-selected URLs use `network_policy: :public`, which rejects loopback and
private targets. Lightpanda has no graphical renderer, so the report always
states that pixel appearance and responsive breakpoints were not verified.

The sitemap itself is generated separately at `/sitemap.xml`; `robots.txt` is a
plain static file.

## Public blog and SEO surfaces

| URL | Purpose |
| --- | --- |
| `/` and `/:lang` | published article index |
| `/:lang/:slug` | rendered article |
| `/tag/:tag` | tag archive, optionally filtered with `?lang=<code>` |
| `/category/:category` | category archive |
| `/feed.xml` | RSS |
| `/atom.xml` | Atom |
| `/sitemap.xml` | dynamic sitemap generated from published articles |
| `/robots.txt` | static crawler policy |
| `/health` | secret-free health check |
| `/mcp` | Streamable HTTP MCP endpoint |
| `/.well-known/*` and `/oauth/*` | OAuth discovery, registration, consent, token, and revocation |

Drafts are absent from public pages, feeds, and sitemap output. Article pages
include canonical metadata, Open Graph data, JSON-LD, translation alternates,
and ETags derived from the indexed Git commit.

## MCP and ChatGPT

The same action surface is available through Streamable HTTP MCP. Direct
operator clients use:

```text
Authorization: Bearer <EX_BLOG_MCP_TOKEN>
```

ChatGPT uses OAuth 2.1 instead of that shared bearer:

1. configure the MCP URL as `https://<PHX_HOST>/mcp`;
2. ChatGPT discovers the `/.well-known/` metadata and dynamically registers;
3. authorization opens the same protected administrator login and consent;
4. the authorization-code flow requires PKCE S256;
5. scopes separate `articles:read`, `articles:write`, and `offline_access`.

Access tokens last 15 minutes. Refresh tokens last 30 days and rotate on every
use. Plaintext tokens are returned to the client only once;
`$EX_BLOG_DATA_DIR/runtime.dets` stores SHA-256 hashes, expiry, scopes, and
revocation state. Keep the data volume to preserve the ChatGPT authorization
across deployments; if the volume is lost, authorize again.

Use `EX_BLOG_CHATGPT_PUBLIC_BASE_URL` only when the externally visible HTTPS
origin differs from `https://<PHX_HOST>`, such as a development tunnel. Do not
append `/mcp`.

## Boot sequence and operating model

```text
validate every ENV
→ create the data directory
→ restore durable article images
→ open DETS
→ restore semantic routing examples
→ clone or synchronize the Git repository
→ parse Markdown and build ETS
→ start Spectre, Prism, Kinetic, and Beam boundaries
→ start the ExGram session
→ expose Phoenix and MCP
```

GitHub is the durable source for text content. The data volume is durable
operational state. ETS is disposable and is rebuilt from Git. There is no Ecto
repository and no SQL migration step.

If the application cannot validate configuration, open the content checkout,
or start the Telegram transport, boot fails instead of exposing a partially
working agent.

## Tests and quality

Run the complete project gate:

```bash
mix precommit
```

It runs compilation with warnings as errors, removes unused lock entries,
formats the project, runs Credo in strict mode, runs Dialyzer with unmatched
return and error-path checks, and executes the test suite.

The individual commands are:

```bash
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test
```

When changing a rendered public page, also run:

```bash
mix spectre.lens.doctor
```

Then inspect the affected route with Spectre Lens. Use a Remote CDP backend
when pixel-level or responsive visual verification is required.

## Production notes

The included Fly configuration assumes:

- `EX_BLOG_DATA_DIR=/data`;
- one persistent volume mounted at `/data`;
- one active machine, because DETS, TDLib, the checkout, and article images are
  local to that volume;
- `PHX_SERVER=true` and HTTPS at the edge;
- GitHub as the recoverable source of Markdown content.

Generate production secrets locally:

```bash
ADMIN_HASH="$(mix ex_blog.admin.hash_password 'choose-at-least-12-characters')"

fly secrets set \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  EX_BLOG_ADMIN_PASSWORD_HASH="$ADMIN_HASH" \
  EX_BLOG_ADMIN_TELEGRAM_ID="123456789" \
  EX_BLOG_TELEGRAM_API_ID="12345" \
  EX_BLOG_TELEGRAM_API_HASH="..." \
  EX_BLOG_GITHUB_TOKEN="github_pat_..." \
  EX_BLOG_GITHUB_REPOSITORY="owner/blog-content" \
  OPENROUTER_API_KEY="sk-or-..." \
  EX_BLOG_LLM_FAST_MODEL="provider/fast-model" \
  EX_BLOG_LLM_BALANCED_MODEL="provider/balanced-model" \
  EX_BLOG_LLM_DEEP_MODEL="provider/deep-model" \
  EX_BLOG_CLASSIFIER_MODEL="provider/fast-model" \
  EX_BLOG_MCP_TOKEN="$(openssl rand -hex 32)"
```

Set non-secret deployment values such as branch, languages, budgets, host,
embedding model, and port in `fly.toml` or the platform environment.

The native `tdlib-json-cli` executable must be present in every production
release. Build it with `mix ex_gram.setup_tdlib` before `mix release`, or
provide a reviewed executable through ExGram's `:backend_binary`
configuration. Normal dependency compilation intentionally does not build
TDLib.

Do not use a release command for content setup: the checkout and DETS files
must be opened by the machine that owns the mounted volume.

## Further reading

- [Markdown content contract](docs/content-contract.md)
- [Architecture decisions](docs/architecture.md)
- [Spectre editorial walkthrough](docs/spectre-editorial-showcase.md)
- [ExGram](https://github.com/elchemista/ex_gram)
- [Telegram API application credentials](https://core.telegram.org/api/obtaining_api_id)
- [GitHub fine-grained personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
