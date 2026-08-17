import Config

config :ex_blog,
  validate_runtime_config?: false,
  start_content?: false,
  # Tests that need the compatibility matrix start the process themselves with a
  # stubbed transport. Nothing else may reach GitHub Pages during a test run.
  start_ecosystem?: false,
  start_telegram?: false,
  spectre_embedding_adapter: Spectre.Classifier.Embeddings.ExFastembed

# Tests opt into planner doubles explicitly. An unexpected deterministic
# planner failure must not turn into a real network request.
config :ex_blog, :kinetic_planner_llm, nil
config :ex_blog, :kinetic_planner_llm_fallbacks, nil

# Unit tests inject deterministic classifier/embedding adapters. Avoid loading
# the large native model merely because locally generated artifacts exist.
config :spectre, :classifier,
  artifact_dir: "tmp/test-spectre-classifier",
  start?: false,
  required?: false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ex_blog, ExBlogWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "OFAifNq5FAb74eVj16R7FMGXeS5BvGtl6UbZjm9e6G6G6nRFdxksfXNhLHnOGTZm",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
