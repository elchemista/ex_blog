# Showcase: agentic publishing with Spectre

ExBlog uses Spectre as an application runtime, not as a thin chat wrapper. A
model may propose text, but flows, skills, policies, state, and typed effects
decide what can actually happen. The result is a conversational Telegram editor
that remains deterministic at security-sensitive boundaries and observable in
tests.

## Responsibility map

```text
ExGram / Telegram
└── Spectre Beam: channel normalization and authenticated identity
    └── Spectre Agent
        ├── Reader skill: article discovery and public blog audits
        ├── Editorial skill: workflows, generation, and protected mutations
        └── Operations skill: configuration, budget, provider health, and Git sync
            ├── Spectre Prism: OpenRouter model-tier selection
            ├── optional local classifier: development/test evaluation
            ├── OpenRouter embeddings: production semantic routing
            ├── Semantic Cache + Vettore: verified reuse of read intents
            ├── Spectre Kinetic: Action Language → typed action
            └── Spectre Policy: confirmation → executable effect
```

The separation is intentional:

- Beam knows which authenticated channel produced a message without knowing
  editorial business rules;
- each skill owns its conversation and route policy without embedding Git or
  HTTP implementation details;
- Prism and OpenRouter generate bounded values but cannot advance a workflow or
  write a file by themselves;
- the optional classifier and semantic cache recognize intent but never grant
  authorization;
- Kinetic translates only valid Action Language declared by the `@al` catalog;
- Spectre owns policy, persistence, idempotency, and effect execution;
- `ExBlog.Content.Writer` remains the only canonical Markdown write boundary.

The agent's operating language is English. Classifier examples, HEEx prompts,
confirmation requests, audits, and Telegram replies are all English. Editorial
language is separate workflow data: article bodies, SEO, and translations are
generated in the language selected by the administrator.

## A flow inside a flow

Article creation is declared in `ExBlog.Agent.Skills.Editorial` as the
`:editorial` flow, containing the `:article_creation` flow and five leaf flows:

```text
/create
  → article_brief
  → article_language
  → article_category ── "generate category" → OpenRouter fast
  → article_title    ── "generate title"    → OpenRouter balanced
  → article_seo      ── "generate SEO" | "skip"
  → CREATE ARTICLE ...
  → confirmation policy
  → OpenRouter deep for the body
  → OpenRouter balanced for SEO and tags when requested
  → Writer → Git → ETS rebuild
```

The DETS-backed state store persists `current_flow` and `current_scope` between
messages. `CreationContinuation` reads that cursor and assigns free-text replies
to the active leaf without paying for or risking a fresh classification on
every field. Global `/cancel` and `/attach-image` controls keep precedence. An
image attachment returns to the exact same workflow step.

The continuation boundary is also why an answer such as `English`, `Platform
engineering`, or `generate SEO` is interpreted as field data while intake is
active. An explicit slash command remains the administrator's escape hatch for
invoking another operation.

Language selection is deterministic. `ExBlog.Agent.Language` recognizes codes
and English language names, then accepts only values present in
`EX_BLOG_SUPPORTED_LANGUAGES`. A reply such as `English` or `write it in
Italian` does not require the LLM classifier.

This is a useful property of Spectre flows: the flow expresses the shape of the
conversation, while global interrupts handle orthogonal events without
spreading conditional logic through the Telegram transport.

## Fine-grained AI generation

The administrator decides which fields the model should generate:

| Part | Workflow request | Tier | Immediate effect |
| --- | --- | --- | --- |
| category | `generate category` | fast | updates Spectre state only |
| title | `generate title` | balanced | updates Spectre state only |
| body | always generated after approval | deep | prepares canonical Markdown |
| SEO and tags | `generate SEO` | balanced | adds validated front matter to the new draft |
| existing SEO | `/seo en article-slug` | balanced | stages a protected Git update |
| translation | `/translate en article-slug to it` | deep | stages creation of a translated draft |

Intermediate generation passes through `ExBlog.Agent.EditorialAI`. Each helper
is a read-only leaf: it returns one normalized, length-limited value, does not
own state, and cannot mutate the repository. The body and optional SEO are
generated inside `ExBlog.Agent.Actions.create_article/2` only after Spectre has
received confirmation. Rejecting the effect therefore cannot leave a partial
article behind.

## HEEx prompts as reviewable application code

Prompts are not assembled from string fragments in callbacks. They are compiled
HEEx templates under `lib/ex_blog_web/prompts`:

- `renderers/` contains reusable OpenRouter generation and transformation
  prompts;
- `skills/editorial/` contains workflow questions and replies;
- `skills/editorial/policies/` contains the confirmation boundary;
- the agent root contains the English classifier prompt.

Every dynamic value crosses `ExBlogWeb.Prompt.escape_text/2`, which applies
credential redaction, a length bound, and HTML escaping before rendering. Prompt
templates remain readable in code review and can be tested independently of the
workflow callbacks.

## Multi-provider routing

The router collects evidence in this order:

```text
explicit slash command or safety regex
  → continuation of the active leaf flow
  → exact trusted dataset or verified-cache match
  → optional local classifier when enabled
  → verified semantic vector search
  → arbitration
  → llm_classifier fallback
```

Regex is intentionally narrow. It handles explicit `/...` commands, safety
patterns, confirmation responses, cancellation, and image control. Natural
English requests are handled by semantic examples, the optional classifier,
the verified semantic cache, and finally the remote classifier.

Every route declares its own `via:` providers:

- read routes expose regex, optional static embeddings, the local classifier,
  semantic cache, and the LLM fallback;
- editorial and repository mutations expose regex, optional static embeddings,
  and both classifiers, but opt out of semantic-cache learning;
- article-intake leaves expose only the private
  `:creation_continuation` provider.

`regex_strength: :hard` is provider-specific. A real slash-command match is
decisive, but an embedding candidate attached to the same rule still needs to
pass score and margin gates.

## An ExBlog-specific trained dataset

The canonical corpus is `priv/spectre/dataset.json`. It contains 204 original
English examples: 12 examples for each of 17 classifier-visible ExBlog intents.
It deliberately includes nearby but distinct requests such as:

- list the archive versus search the archive;
- inspect one article versus audit its rendered public page;
- generate SEO versus revise the article body;
- publish content versus synchronize the Git repository;
- valid editorial work versus unknown or unsafe requests.

The nested capture leaves are excluded because the persisted workflow cursor,
not a model, owns their answers. The dataset task validates labels against the
compiled Agent definition, rejects duplicate normalized text, enforces English,
and requires complete intent coverage:

```bash
mix ex_blog.spectre.dataset.build --check
```

Development/test classifier bootstrap is reproducible:

```bash
MIX_ENV=dev mix spectre.classifier.setup
```

It normalizes the training corpus, downloads
`intfloat/multilingual-e5-small`, trains a centroid classifier, and writes a
vectorized semantic-cache mirror under `artifacts/spectre`. Dataset source is
committed; generated model weights, vectors, and the local model cache are
ignored by Git and excluded from the production image.

## Environment-specific embedding boundary

`ExBlog.Agent.Embedding` follows the same split used by the reference Freelance
application:

- development and test delegate to ExFastembed. E5's `query:` prefix is applied
  during training and inference, and the same 384-dimensional model powers the
  optional centroid classifier and local semantic mirror;
- production delegates to `ExBlog.AI.Embedding`. Text is redacted and sent to
  the configured OpenRouter embedding model through Req, budget authorization,
  and usage accounting. Hosted text does not receive the E5-specific prefix.

ExFastembed is declared `only: [:dev, :test], runtime: false`. Production also
sets `local_classifier_enabled?: false`, `start?: false`, and
`artifact_dir: nil`. The runtime image contains no ExFastembed dependency,
native embedding-model cache, local classifier, or 384d semantic artifact. Its
build-only Rust stage exists for Spectre Kinetic's Ortex NIF and is not copied
into the runtime image.

This separation prevents dimension drift. DETS semantic snapshots include the
adapter/model/dimension identity in their storage key, so local 384d rows and
hosted 1,024d rows cannot be restored into the same index. When enabled in
development, local results must still meet both score and label-margin gates;
an ambiguous result falls through to later evidence.

## Semantic cache lifecycle

The seven read-only intents declare `learn: true`. When the LLM fallback first
classifies a new eligible phrase, Spectre may store it as an unverified online
example. `ExBlog.Agent.SemanticCache` persists the row and its embedding in DETS
so a deployment does not erase reviewed routing knowledge.

This showcase has no review UI. An unverified example is not used by normal
search. A later request may promote it only at `0.985` cosine similarity with at
least a `0.05` margin over competing labels. Ordinary verified search remains
at `0.94`.

The local development artifact contains vectors for all 204 classifier
examples, but route policy filters its runtime index to the 84 examples
belonging to cacheable read intents. Production does not load that artifact: it
uses the checked-in dataset for exact matches and OpenRouter for new learned
semantic rows. Writes, deletion, synchronization, unsafe input, and unknown
input can train local intent evaluation without becoming reusable semantic
authorization. A cache hit can select a read handler; it can never approve a
policy or execute a Git mutation.

## Kinetic and `@al`

The operational catalog lives in the Elixir module
`ExBlog.Agent.KineticActions`. `use SpectreKinetic` derives names, parameters,
types, documentation, and examples directly from `@al`, `@spec`, and `@doc`.

The creation wizard does not build an arbitrary map and execute it manually. It
produces canonical Action Language similar to:

```text
CREATE ARTICLE TITLE="Reliable agent flows" LANG="en" CATEGORY="AI"
BRIEF="Explain how typed effects protect publishing" GENERATE_SEO=true
COVER="/images/articles/<sha256>.jpg" COVER_ALT="Diagram of the editorial workflow"
```

Kinetic must resolve that text against the typed catalog. Only then does
Spectre create an effect owned and scoped by the Editorial skill and apply
`:editorial_confirmation`. The local provider calls the domain implementation
only when the effect is approved and executable.

This split allows the Action Language vocabulary and selection model to evolve
without moving authorization into a prompt.

## Telegram photos as editorial assets

An image follows a separate input path while remaining inside the same agent:

```text
sender_id == configured administrator
  → Beam decodes :image
  → bounded metadata: file_id, size, redacted caption
  → ATTACH_ARTICLE_IMAGE interrupt
  → verify that article_creation is active
  → ExGram.download_media/3
  → enforce size and inspect magic bytes
  → SHA-256 filename, never the user-provided filename
  → priv/static/images/articles/<sha256>.<ext>
  → cover and cover_alt in workflow state
  → Markdown front matter after confirmation
```

Image bytes never enter DETS, memory, prompts, or chat history. The TDLib
reference is transient, and download occurs only after the numeric
administrator gate and active-flow check. ExBlog accepts JPEG, PNG, WebP, and
GIF files up to 10 MB; SVG and arbitrary documents are rejected.

The public copy lives in `priv/static/images/articles`. A content-addressed
copy is also kept under `$EX_BLOG_DATA_DIR/assets/images/articles` and restored
into `priv` at startup because a release directory is replaced during a deploy.
The Markdown path `/images/articles/...` therefore remains stable.

The Telegram caption becomes `cover_alt`. When it is absent, the workflow uses
a title-based fallback; supplying a caption that describes the visible content
is still the accessible choice.

## Policies and trust boundaries

- `EX_BLOG_ADMIN_TELEGRAM_ID` is checked before Beam, Spectre, downloads, logs,
  and OpenRouter calls.
- Beam marks the authenticated source; `ExBlog.Telegram.Image` rejects input
  that did not originate from the authenticated Telegram mount.
- Generated categories and titles are values, not commands. They are normalized
  to one line and limited to 80 and 160 characters respectively.
- SEO JSON is decoded, validated, and bounded before the Writer receives it.
- Cover paths written by the agent must be HTTPS or root-relative and cannot
  contain traversal segments or backslashes.
- Every Git mutation remains protected by a Spectre policy. A model cannot
  approve its own effect.
- Budget and estimated cost are authorized before every OpenRouter request.
- Input credentials are redacted before routing, memory, state, or prompts, and
  the original `Spectre.Input.raw` value is discarded.

## Extending the showcase

To add an editorial field:

1. add a leaf flow and its terminal label;
2. create the skill's conversational HEEx prompt;
3. when AI is useful, add a bounded renderer and a read-only helper;
4. add a typed parameter to the `@al` action only when the value must reach the
   final effect;
5. test the transition, persisted cursor, extracted Action Language, and policy
   independently.

To add a mutation, declare `requires_action`, register it with the provider,
protect it with a policy, and keep the actual write in a domain boundary. Adding
an instruction to a prompt is not enough: in Spectre, the prompt proposes and
the runtime decides.

To add a read intent, add contrastive English examples to the skill and the
ExBlog dataset, then optionally rerun `MIX_ENV=dev mix
spectre.classifier.setup` for local evaluation. Keep `learn: true` only when
semantic reuse cannot produce a side effect.

## Browser verification

Spectre Lens is deliberately limited to the public blog: article pages, the
index, metadata, links, images, sitemap discovery, and document warnings or
errors. It is not used for Telegram QR pairing or administrator-session
guidance.

Lightpanda verifies DOM structure and semantics but has no graphical rendering
engine. Pixel appearance, CSS behavior, and responsive breakpoints require a
Spectre Lens Remote CDP backend connected to a graphical browser.
