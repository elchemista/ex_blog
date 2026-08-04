# Architecture and security boundaries

## Data ownership

```text
Fly environment and secrets
└── identities, infrastructure settings, credentials, and model identifiers

Git repository
└── Markdown, editorial metadata, content-addressed covers, and history

DETS on the persistent volume
└── Spectre state, reviewed semantic examples, costs, Git history, and revocable OAuth hashes

Assets on the volume plus priv/static
└── runtime mirror and public projection of Git-managed Telegram images

ETS
└── rebuildable read projection of parsed articles

Release priv directory
└── versioned routing dataset; no native classifier or model cache

Ignored development artifacts
└── optional local classifier, 384d semantic mirror, and ExFastembed model cache
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
→ select OpenRouter as the production Spectre embedding adapter
→ restore learned semantic rows and warm the Vettore index
→ clone or synchronize the content repository
→ parse Markdown and publish a new ETS snapshot
→ start Telegram and the Phoenix endpoint
```

A failure in a required step terminates startup. Production requires the
versioned dataset but explicitly rejects local artifact paths and attempts to
enable `SPECTRE_LOCAL_CLASSIFIER`. ExFastembed is not a production dependency.

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
- **Browser:** Spectre Lens starts Lightpanda for `check_page` and bounded
  editorial source research, applies the public-network policy, and always
  closes every tab and runtime. Raw HTML and page text never enter Spectre
  state. Before projected content can reach a model, it passes through
  `SpectreLens.agent_context/2` as untrusted web data.
- **Telegram:** the sender username resolved from ExGram's contact projection
  is checked in the gateway before Beam, media download, prompts, logging, or
  cost accounting. Photos become authenticated Beam inputs containing only
  bounded metadata and a TDLib file identifier. ExGram downloads the bytes only
  inside an active editorial flow.
- **Telegram application credentials:** `TG_API_ID` and `TG_API_HASH` identify
  the Telegram application used by ExGram. They are distinct from the allowed
  administrator username and from the persistent TDLib user session.
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
→ optional local classifier when available in development/test
→ verified vector semantic search
→ arbitration
→ remote LLM classifier fallback
```

Regex is reserved for deterministic controls, safety patterns, confirmation,
and bounded field parsing. Natural-language intent recognition belongs to the
versioned English dataset, the optional local classifier, semantic search, and
the LLM fallback.

`ExBlog.Agent.Embedding` selects its implementation by environment:

- development and test may use ExFastembed with
  `intfloat/multilingual-e5-small` to train a 384-dimensional centroid
  classifier and local semantic mirror;
- production delegates to `ExBlog.AI.Embedding`, which requests the configured
  OpenRouter embedding model through Req and the shared budget ledger. The
  default dimension contract is 1,024.

The checked-in corpus contains 228 original examples across 19
classifier-visible intents. Local training uses all examples for the centroid
classifier and can index the 96 examples belonging to eight cacheable read
routes. Production ships neither local artifact. It keeps dataset exact matches
and embeds new eligible semantic rows through OpenRouter.

Persisted semantic rows are namespaced by the selected embedding model and
dimension identity, preventing a development 384d row from entering the same
DETS snapshot as a production 1,024d row.

New online semantic examples begin unverified and are persisted in DETS. They
can be promoted automatically only when a later request reaches at least
`0.985` cosine similarity and preserves a `0.05` inter-label margin. Normal
verified search requires `0.94`. Only read-only routes declared with
`learn: true` participate, so semantic reuse cannot replace a confirmation
policy or authorize a Git write.

Budget is authorized before each OpenRouter request. After a valid response,
token counts, model, purpose, subject, and cost are recorded in DETS.
Deterministic exact matches do not depend on provider availability. Production
semantic vector search and learning do depend on OpenRouter; failure falls
through to the normal routing error or classifier handling instead of loading a
native model.

## Agent composition and effects

The agent installs three independent `Spectre.Skill` modules:

- **Reader** owns article discovery and public-page audits;
- **Editorial** owns creation, revision, translation, SEO, publication, and
  deletion workflows;
- **Operations** owns safe diagnostics and protected repository
  synchronization.

Article creation uses nested flows for source URLs, directions, language,
category, title, the SEO choice, and draft review. `current_flow` and
`current_scope` persist between messages. The source URL regex is evaluated by
the continuation plug only at the source cursor. Lens converts each page through
the untrusted-content boundary, and only a bounded summary survives in state.
Category and title can be filled by bounded OpenRouter leaf calls. A Telegram
photo is a global interrupt that attaches a cover while leaving the cursor
unchanged.

The deep model produces an in-memory Markdown preview. Free-form revision
instructions loop through another preview; cancellation clears the workflow.
An explicit review confirmation resolves the protected `create_article` effect,
which receives the exact displayed body. Only then may optional SEO generation
and `ExBlog.Content.Writer` perform the canonical repository transaction.

Article lists persist a bounded, conversation-scoped sequence of identifiers.
The same deterministic selector resolves a later number, exact title,
`lang/slug`, public URL, or Git URL and then re-reads the current content index.
Existing-article edits use their own instructions and preview cursors; only the
exact confirmed preview becomes a protected `revise_article` effect. Publishing
by title or number likewise stages the typed effect directly and does not ask a
model to generate Action Language.

Classifier and editorial transformation prompts are compiled HEEx templates.
Dynamic values are redacted, bounded, and escaped before rendering. The full
walkthrough and extension points are documented in
[`spectre-editorial-showcase.md`](spectre-editorial-showcase.md).

## Fly.io operating model

ExBlog uses one machine and one `/data` volume. This is deliberate: DETS, TDLib,
and the working checkout are node-local state, while Markdown and confirmed
covers remain recoverable from GitHub. Telegram images are mirrored under
`/data/assets/images/articles`; startup and repository sync validate Git assets
and restore them into the release `priv/static` directory served at
`/images/articles`.

The container changes ownership only on the volume root and then drops
privileges to the `exblog` user. The runtime image contains no Rust toolchain,
ExFastembed dependency, native embedding-model cache, or local classifier. A
Rust toolchain exists only in the Docker builder because Spectre Kinetic's
Ortex dependency compiles a NIF. The runtime uses the default 1 GB machine for
Phoenix and TDLib.
