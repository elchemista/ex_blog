# Architecture and security boundaries

## Data ownership

```text
Fly environment and secrets
└── identities, infrastructure settings, credentials, and model identifiers

Git repository
└── Markdown, editorial metadata, and content history

DETS on the persistent volume
└── Spectre state, reviewed semantic examples, costs, Git history, and revocable OAuth hashes

Assets on the volume plus priv/static
└── durable backing store and public projection of Telegram images

ETS
└── rebuildable read projection of parsed articles

Release priv directory
└── versioned routing dataset and reproducible trained classifier artifacts
```

Plaintext tokens are never stored in Git, DETS, ETS, Spectre state, or agent
memory. For OAuth, DETS keeps only SHA-256 hashes, expiry times, scopes, and
revocation state. Plaintext access and refresh tokens are returned to the
client once. The complete runtime configuration has a redacted `Inspect`
implementation; the agent and MCP receive only `ExBlog.Config.public/0`.

The checked-in routing corpus contains examples, not conversations or user
content. Generated vectors and model weights are reproducible build artifacts
and are ignored by Git.

## Deterministic boot

`ExBlog.Application` validates the complete environment before exposing the
application. In production it performs the following ordered work:

```text
validate environment
→ create the data directory
→ restore content-addressed public assets
→ open and repair DETS
→ load the trained local classifier
→ restore learned semantic rows and warm the Vettore index
→ clone or synchronize the content repository
→ parse Markdown and publish a new ETS snapshot
→ start Telegram and the Phoenix endpoint
```

A failure in a required step terminates startup. Production also treats the
local classifier artifact as required when `SPECTRE_LOCAL_CLASSIFIER=true`, so
a release cannot silently serve with an incomplete build.

An ETS rebuild populates a new table. One `:persistent_term` update publishes
the complete snapshot, after which the old table is deleted. Readers retry if
they happen to access the index during the swap.

## Credential boundaries

- **GitHub:** the remote remains `https://github.com/owner/repository.git`. The
  token exists only in the environment of a temporary `GIT_ASKPASS` process;
  it is never embedded in the remote URL.
- **OpenRouter:** the token is resolved by the transport immediately before a
  `Req` call. It is not part of the compiled Prism configuration. Req retries
  remain disabled because Prism owns model-level retry policy.
- **Browser:** Spectre Lens starts Lightpanda only for `check_page`, applies the
  public-network policy, and always closes the tab and runtime. Raw HTML and
  page text never enter Spectre state. Before projected content can reach a
  model, it passes through `SpectreLens.agent_context/2` as untrusted web data.
- **Telegram:** the numeric sender ID is checked in the gateway before Beam,
  media download, prompts, logging, or cost accounting. Photos become
  authenticated Beam inputs containing only bounded metadata and a TDLib file
  identifier. ExGram downloads the bytes only inside an active editorial flow.
- **Telegram application credentials:** `TG_API_ID` and `TG_API_HASH` identify
  the Telegram application used by ExGram. They are distinct from the allowed
  administrator ID and from the persistent TDLib user session.
- **MCP:** every request validates its Origin and protocol version. An OAuth
  bearer is checked against its DETS hash, resource, expiry, revocation state,
  and scopes. The environment-backed operator token remains available to
  direct administrative clients. Error responses do not serialize internal
  exceptions.
- **ChatGPT OAuth:** RFC 8414 and RFC 9728 discovery, dynamic registration,
  consent in the protected admin session, PKCE S256, single-use authorization
  codes, 15-minute access tokens, and rotating refresh tokens are implemented
  without Ecto. One DETS transaction makes code consumption and token rotation
  atomic. The persistent volume preserves authorization across deployments;
  losing it requires authorization again. Phoenix filters tokens, codes, and
  verifiers from logged parameters.

## Models, routing, and cost

Prism receives non-sensitive markers such as `runtime-fast`,
`runtime-balanced`, and `runtime-deep`. The OpenRouter adapter resolves those
markers to environment-provided model identifiers at call time. The remote LLM
classifier has its own configured model even when it shares the fast tier.

The editorial agent and all operational prompts use English. Article language
is separate workflow data. `ExBlog.Agent.Language` deterministically resolves a
supported code or English language name against
`EX_BLOG_SUPPORTED_LANGUAGES`; body, SEO, and translation prompts then receive
the selected target language explicitly.

Intent routing is an evidence pipeline, not a collection of broad regular
expressions:

```text
explicit slash command or safety regex
→ active nested-flow continuation
→ exact trusted dataset or verified-cache match
→ trained local classifier
→ verified vector semantic search
→ arbitration
→ remote LLM classifier fallback
```

Regex is reserved for deterministic controls, safety patterns, confirmation,
and bounded field parsing. Natural-language intent recognition belongs to the
versioned English dataset, the local classifier, semantic search, and the LLM
fallback.

The local classifier and semantic cache share
`intfloat/multilingual-e5-small` through `ExBlog.Agent.Embedding`. The adapter
applies E5's `query:` prefix during training and inference, producing compatible
384-dimensional vectors without spending OpenRouter budget. The checked-in
corpus contains 204 original examples across 17 classifier-visible intents.
Training uses all examples for the centroid classifier; boot indexes only the
84 examples belonging to the seven cacheable read routes.

`ExBlog.AI.Embedding` remains available as an optional hosted Prism capability,
but it is not used by the agent's intent-routing hot path.

New online semantic examples begin unverified and are persisted in DETS. They
can be promoted automatically only when a later request reaches at least
`0.985` cosine similarity and preserves a `0.05` inter-label margin. Normal
verified search requires `0.94`. Only read-only routes declared with
`learn: true` participate, so semantic reuse cannot replace a confirmation
policy or authorize a Git write.

Budget is authorized before each OpenRouter request. After a valid response,
token counts, model, purpose, subject, and cost are recorded in DETS.
Deterministic and local-model operations do not depend on provider
availability.

## Agent composition and effects

The agent installs three independent `Spectre.Skill` modules:

- **Reader** owns article discovery and public-page audits;
- **Editorial** owns creation, revision, translation, SEO, publication, and
  deletion workflows;
- **Operations** owns safe diagnostics and protected repository
  synchronization.

Article creation uses nested flows for brief, language, category, title, and
the SEO choice. `current_flow` and `current_scope` persist between messages.
Category and title can be filled by bounded OpenRouter leaf calls that cannot
mutate Git. A Telegram photo is a global interrupt that attaches a cover while
leaving the flow cursor unchanged.

After intake, Kinetic validates a typed `CREATE ARTICLE` command against the
Elixir `@al` catalog. Spectre still owns confirmation, effect persistence,
idempotency, and execution. Only after approval may OpenRouter generate the
body and optional SEO and may `ExBlog.Content.Writer` perform the canonical
repository transaction.

Classifier and editorial transformation prompts are compiled HEEx templates.
Dynamic values are redacted, bounded, and escaped before rendering. The full
walkthrough and extension points are documented in
[`spectre-editorial-showcase.md`](spectre-editorial-showcase.md).

## Fly.io operating model

ExBlog uses one machine and one `/data` volume. This is deliberate: DETS, TDLib,
and the working checkout are node-local state, while Markdown remains
recoverable from GitHub. Telegram images have a durable backing store under
`/data/assets/images/articles`; startup restores them into the release
`priv/static` directory served at `/images/articles`.

The container changes ownership only on the volume root and then drops
privileges to the `exblog` user. The default machine uses 2 GB of memory because
Phoenix, TDLib, and the warm local embedding model share the same runtime.
