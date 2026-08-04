# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ex_blog,
  validate_runtime_config?: true,
  start_content?: true,
  start_telegram?: true,
  secure_session_cookie?: config_env() == :prod,
  semantic_cache: [
    search_threshold: 0.94,
    auto_verify_threshold: 0.985,
    auto_verify_margin: 0.05
  ]

# The local classifier and semantic cache use one encoder. Training emits both
# `classifier.etf` and a `semantic_cache.jsonl` mirror containing the same
# vectors, so application boot can warm Vettore without re-embedding the corpus.
config :spectre, :classifier,
  artifact_dir: "priv/spectre/classifier",
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
