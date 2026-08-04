import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/ex_blog start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :ex_blog, ExBlogWeb.Endpoint, server: true
end

config :ex_blog, ExBlogWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

data_dir =
  System.get_env("EX_BLOG_DATA_DIR") ||
    if(config_env() == :test, do: Path.expand("../tmp", __DIR__), else: "/data")

config :ex_blog,
  runtime_environment: config_env(),
  runtime_data_dir: data_dir

# The checked-in dataset is always release-safe. Classifier artifacts are
# generated during the image build and resolved through the release priv dir;
# explicit paths remain available for operators mounting prebuilt artifacts.
classifier_config = Application.get_env(:spectre, :classifier, [])

classifier_env_path = fn name ->
  case System.get_env(name) do
    value when is_binary(value) ->
      value = String.trim(value)
      if value == "", do: nil, else: value

    _missing ->
      nil
  end
end

classifier_dataset_path =
  classifier_env_path.("SPECTRE_CLASSIFIER_DATASET_PATH") ||
    if(config_env() == :prod,
      do: ExBlog.Agent.ClassifierConfig.release_dataset_path(),
      else: Keyword.fetch!(classifier_config, :dataset_path)
    )

classifier_artifact_dir =
  classifier_env_path.("SPECTRE_CLASSIFIER_ARTIFACT_DIR") ||
    if(config_env() == :prod,
      do: ExBlog.Agent.ClassifierConfig.release_artifact_dir(),
      else: Keyword.fetch!(classifier_config, :artifact_dir)
    )

local_classifier_enabled? =
  case System.get_env("SPECTRE_LOCAL_CLASSIFIER") do
    nil ->
      Keyword.get(classifier_config, :local_classifier_enabled?, true)

    value when is_binary(value) ->
      case value |> String.trim() |> String.downcase() do
        enabled when enabled in ["1", "true", "yes"] ->
          true

        disabled when disabled in ["0", "false", "no"] ->
          false

        invalid ->
          raise "SPECTRE_LOCAL_CLASSIFIER must be true or false, got: #{inspect(invalid)}"
      end
  end

config :spectre, :classifier,
  dataset_path: classifier_dataset_path,
  artifact_dir: classifier_artifact_dir,
  local_classifier_enabled?: local_classifier_enabled?,
  start?: local_classifier_enabled? and Keyword.get(classifier_config, :start?, true),
  required?: config_env() == :prod and local_classifier_enabled?

case System.get_env("EX_BLOG_CHATGPT_PUBLIC_BASE_URL") do
  value when is_binary(value) and value != "" ->
    case URI.parse(value) do
      %URI{
        scheme: "https",
        host: host,
        port: port,
        path: path,
        query: nil,
        fragment: nil,
        userinfo: nil
      }
      when is_binary(host) and port in [nil, 443] and path in [nil, "", "/"] ->
        config :ex_blog, :chatgpt_public_base_url, String.trim_trailing(value, "/")

      _invalid ->
        raise "EX_BLOG_CHATGPT_PUBLIC_BASE_URL must be an HTTPS origin without path or credentials"
    end

  _missing ->
    :ok
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :ex_blog, ExBlogWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/ex_blog_web/router\.ex$"E,
        ~r"lib/ex_blog_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  # ExBlog.Config validates these together with every other required variable
  # before the supervision tree starts. Placeholders keep runtime configuration
  # evaluation from masking the aggregated boot error.
  secret_key_base = System.get_env("SECRET_KEY_BASE") || String.duplicate("0", 64)
  host = System.get_env("PHX_HOST") || "localhost"

  config :ex_blog, ExBlogWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :ex_blog, ExBlogWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :ex_blog, ExBlogWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
