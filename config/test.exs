import Config

config :ex_blog,
  validate_runtime_config?: false,
  start_content?: false,
  start_telegram?: false

config :ex_blog, ExBlog.Repo,
  database: Path.expand("../tmp/ex_blog_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

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
