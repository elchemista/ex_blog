# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Source strings live in English; every other language ships as a Gettext
# translation under priv/gettext.
config :gettext, :default_locale, "en"

config :ex_blog,
  validate_runtime_config?: true,
  start_content?: true,
  start_ecosystem?: true,
  start_telegram?: true,
  # The Spectre Studio connection also needs EX_BLOG_PULSE_TOKEN; this flag only
  # keeps the runtime out of the supervision tree when a deployment or a test
  # never wants it, even with a token present.
  start_pulse?: true,
  secure_session_cookie?: config_env() == :prod,
  public_origins: ["http://localhost:4000", "http://127.0.0.1:4000"],
  cors_origins: ["http://localhost:4000", "http://127.0.0.1:4000"],
  semantic_cache: [
    search_threshold: 0.94,
    auto_verify_threshold: 0.985,
    auto_verify_margin: 0.05
  ]

# The compatibility matrix rendered on the home page. The upstream job
# republishes status.json once a day after its scheduled compatibility run, so
# matching that cadence is enough; a failed refresh retries sooner and keeps the
# previous snapshot on screen.
config :ex_blog, :ecosystem,
  status_url: "https://elchemista.github.io/spectre_ecosystem/status.json",
  refresh_interval_ms: 86_400_000,
  retry_interval_ms: 1_800_000

# Kinetic remains deterministic-first. Only a failed deterministic action plan
# reaches this constrained LLM boundary, which is intentionally independent
# from Prism's conversational and classifier model selection.
config :ex_blog, :kinetic_planner_llm,
  adapter: ExBlog.AI.OpenRouter,
  model: "openrouter:qwen/qwen3-next-80b-a3b-instruct"

# This is provider failover for the constrained planner contract, not a retry
# of the same model and never a fallback for route classification.
config :ex_blog, :kinetic_planner_llm_fallbacks, [
  [
    adapter: ExBlog.AI.OpenRouter,
    model: "openrouter:google/gemini-2.5-flash-lite"
  ]
]

# Development and test can share one local encoder between classifier training
# and semantic search. Production overrides the adapter and disables the local
# artifact so hosted 1,024-dimensional vectors never mix with local 384d rows.
config :spectre, :classifier,
  artifact_dir: "artifacts/spectre",
  dataset_path: "priv/spectre/dataset.json",
  encoder_model: "intfloat/multilingual-e5-small",
  embedding_adapter: ExBlog.Agent.Embedding,
  local_classifier_mode: :centroid,
  local_classifier_enabled?: true,
  local_accept_threshold: 0.89,
  local_margin_threshold: 0.008,
  local_high_confidence_threshold: 0.95,
  # The first load may download model weights. Normal in-memory inference is
  # fast, while the router's own deadline still bounds an administrator turn.
  embedding_timeout: 300_000,
  start?: true,
  required?: false

# Spectre keeps only a small number of immutable Vettore projections per
# agent. Online rows themselves are persisted by ExBlog.Agent.SemanticCache.
config :spectre, :semantic_cache,
  index_capacity: 4,
  mirror_training_dataset?: true

# Phoenix Analytics is first-party and stays in memory while it is being
# evaluated: the ETS store needs no database and no third-party request, and in
# exchange the request logs live on the node and are lost on restart. One
# request measures around 1 KB, so the cap below is roughly 100 MB on the 1 GB
# machine; `PhoenixAnalytics.Store.info/0` reports the real usage.
# `cache_ttl: 0` because in-memory folds are cheap enough that a stale
# dashboard buys nothing.
config :phoenix_analytics,
  store: {PhoenixAnalytics.Store.ETS, retention_days: 30, max_entries: 100_000},
  app_domain: "localhost",
  cache_ttl: 0

# Durability is deliberately not configured yet. Snapshots to S3 need
# `{:ex_aws, "~> 2.5"}` and `{:ex_aws_s3, "~> 2.5"}` in mix.exs plus:
#
#     config :phoenix_analytics,
#       snapshot: [
#         sink: {PhoenixAnalytics.Snapshot.Sink.S3, bucket: "...", region: "..."},
#         every: :day,
#         at: ~T[03:00:00],
#         window: :previous_day,
#         format: :etf,
#         gzip: true,
#         restore: [days: 7]
#       ]
#
# `PhoenixAnalytics.Snapshot.Sink.Local` writes to a path instead, which the
# mounted volume would already back up.

# Configure the endpoint
config :ex_blog, ExBlogWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ExBlogWeb.ErrorHTML, json: ExBlogWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ExBlog.PubSub,
  live_view: [signing_salt: "d/fPmgL8"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  ex_blog: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  ex_blog: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason
config :phoenix, :filter_parameters, ["password", "token", "code", "verifier", "secret"]

config :ex_gram, :backend_verbosity_level, 0
config :ex_gram, :log_unhandled_updates, false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
