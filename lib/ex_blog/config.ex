defmodule ExBlog.Config do
  @moduledoc """
  Typed runtime configuration for ExBlog.

  Secrets are loaded only at application boot and are intentionally excluded
  from the public projection. Callers that need a credential must request one
  explicitly with `fetch_secret!/1`; the complete configuration must never be
  passed to prompts, Spectre state, logs, or MCP responses.
  """

  @storage_key {__MODULE__, :runtime}

  @required ~w(
    EX_BLOG_ADMIN_PASSWORD_HASH
    EX_BLOG_ADMIN_TELEGRAM_ID
    EX_BLOG_TELEGRAM_API_ID
    EX_BLOG_TELEGRAM_API_HASH
    EX_BLOG_GITHUB_TOKEN
    EX_BLOG_GITHUB_REPOSITORY
    EX_BLOG_GITHUB_BRANCH
    OPENROUTER_API_KEY
    EX_BLOG_LLM_FAST_MODEL
    EX_BLOG_LLM_BALANCED_MODEL
    EX_BLOG_LLM_DEEP_MODEL
    EX_BLOG_CLASSIFIER_MODEL
    EX_BLOG_MCP_TOKEN
  )

  @production_required ~w(SECRET_KEY_BASE PHX_HOST)

  @secret_fields [
    :admin_password_hash,
    :github_token,
    :openrouter_api_key,
    :telegram_api_hash,
    :mcp_token
  ]

  @derive {Inspect, except: @secret_fields}
  @enforce_keys [
    :admin_password_hash,
    :admin_telegram_id,
    :github_repository,
    :github_branch,
    :fast_model,
    :balanced_model,
    :deep_model,
    :classifier_model,
    :embedding_model,
    :embedding_dimensions,
    :default_language,
    :supported_languages,
    :monthly_budget_eur,
    :max_article_cost_eur,
    :usd_eur_rate,
    :github_author_name,
    :github_author_email,
    :data_dir,
    :content_root,
    :git_sync_interval_ms,
    :telegram_api_id,
    :telegram_session_id,
    :github_token,
    :openrouter_api_key,
    :telegram_api_hash,
    :mcp_token
  ]

  defstruct @enforce_keys ++ [:admin_telegram_username, :phx_host]

  @type t :: %__MODULE__{
          admin_password_hash: String.t(),
          admin_telegram_id: pos_integer(),
          admin_telegram_username: String.t() | nil,
          github_repository: String.t(),
          github_branch: String.t(),
          fast_model: String.t(),
          balanced_model: String.t(),
          deep_model: String.t(),
          classifier_model: String.t(),
          embedding_model: String.t(),
          embedding_dimensions: pos_integer(),
          default_language: String.t(),
          supported_languages: [String.t()],
          monthly_budget_eur: Decimal.t(),
          max_article_cost_eur: Decimal.t(),
          usd_eur_rate: Decimal.t(),
          github_author_name: String.t(),
          github_author_email: String.t(),
          data_dir: String.t(),
          content_root: String.t(),
          git_sync_interval_ms: pos_integer(),
          telegram_api_id: pos_integer(),
          telegram_session_id: String.t(),
          phx_host: String.t() | nil,
          github_token: String.t(),
          openrouter_api_key: String.t(),
          telegram_api_hash: String.t(),
          mcp_token: String.t()
        }

  @doc "Returns the required deployment variables in validation order."
  @spec required_env_names(keyword()) :: [String.t()]
  def required_env_names(opts \\ []) do
    if Keyword.get(opts, :production?, false),
      do: @required ++ @production_required,
      else: @required
  end

  @doc "Loads and validates a configuration from an environment-shaped map."
  @spec load(map(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def load(env \\ System.get_env(), opts \\ []) when is_map(env) do
    required = required_env_names(opts)
    missing = Enum.filter(required, &blank?(Map.get(env, &1)))

    if missing == [] do
      build(env)
    else
      {:error, format_errors(missing, [])}
    end
  end

  @doc "Loads a configuration or raises a redaction-safe boot exception."
  @spec load!(map(), keyword()) :: t()
  def load!(env \\ System.get_env(), opts \\ []) do
    case load(env, opts) do
      {:ok, config} -> config
      {:error, message} -> raise ExBlog.ConfigError, message: message
    end
  end

  @doc false
  @spec install(t()) :: :ok
  def install(%__MODULE__{} = config) do
    :persistent_term.put(@storage_key, config)
    :ok
  end

  @doc "Returns the validated runtime configuration."
  @spec get() :: t()
  def get do
    case :persistent_term.get(@storage_key, :missing) do
      %__MODULE__{} = config -> config
      :missing -> raise ExBlog.ConfigError, message: "ExBlog runtime configuration is not loaded."
    end
  end

  @doc "Returns one credential to the infrastructure module that owns its use."
  @spec fetch_secret!(
          :admin_password_hash
          | :github_token
          | :openrouter_api_key
          | :telegram_api_hash
          | :mcp_token
        ) ::
          String.t()
  def fetch_secret!(name) when name in @secret_fields do
    get()
    |> Map.fetch!(name)
  end

  @doc "Redacts every configured credential from a string."
  @spec redact(String.t(), t()) :: String.t()
  def redact(value, config \\ get()) when is_binary(value) and is_struct(config, __MODULE__) do
    Enum.reduce(@secret_fields, value, fn field, redacted ->
      case Map.fetch!(config, field) do
        secret when is_binary(secret) and secret != "" ->
          String.replace(redacted, secret, "[REDACTED]")

        _other ->
          redacted
      end
    end)
  end

  @doc "Returns the safe configuration projection exposed to the agent and MCP."
  @spec public(t()) :: map()
  def public(config \\ get())

  def public(%__MODULE__{} = config) do
    %{
      repository: config.github_repository,
      branch: config.github_branch,
      default_language: config.default_language,
      supported_languages: config.supported_languages,
      models: %{
        fast: config.fast_model,
        balanced: config.balanced_model,
        deep: config.deep_model,
        classifier: config.classifier_model,
        embedding: config.embedding_model
      },
      agent_language: "en",
      github_token: :configured,
      openrouter_token: :configured,
      telegram_api: :configured,
      mcp_token: :configured,
      monthly_budget_eur: Decimal.to_string(config.monthly_budget_eur),
      max_article_cost_eur: Decimal.to_string(config.max_article_cost_eur)
    }
  end

  @doc "Canonical HTTPS URL used by feeds, sitemap, and metadata."
  @spec canonical_url(t()) :: String.t()
  def canonical_url(config \\ get()) do
    "https://#{config.phx_host || "localhost"}"
  end

  @doc "GitHub HTTPS remote without embedded credentials."
  @spec repository_url(t()) :: String.t()
  def repository_url(config \\ get()) do
    "https://github.com/#{config.github_repository}.git"
  end

  @doc "Absolute checkout directory on the configured volume."
  @spec repository_path(t()) :: String.t()
  def repository_path(config \\ get()), do: Path.join(config.data_dir, "repo")

  @doc false
  @spec test_config(keyword()) :: t()
  def test_config(overrides \\ []) do
    base =
      load!(%{
        "EX_BLOG_ADMIN_PASSWORD_HASH" =>
          "$argon2id$v=19$m=65536,t=3,p=4$/ozmJANXqOhc51VZNhCDpA$ghgiVIIRxNcczcSsqt6Zk2IprX8zSc4fvl9p0+7Xc8c",
        "EX_BLOG_ADMIN_TELEGRAM_ID" => "123456789",
        "EX_BLOG_TELEGRAM_API_ID" => "12345",
        "EX_BLOG_TELEGRAM_API_HASH" => "test-telegram-api-hash",
        "EX_BLOG_GITHUB_TOKEN" => "test-github-token",
        "EX_BLOG_GITHUB_REPOSITORY" => "example/ex-blog-content",
        "EX_BLOG_GITHUB_BRANCH" => "main",
        "OPENROUTER_API_KEY" => "test-openrouter-token",
        "EX_BLOG_LLM_FAST_MODEL" => "test/fast",
        "EX_BLOG_LLM_BALANCED_MODEL" => "test/balanced",
        "EX_BLOG_LLM_DEEP_MODEL" => "test/deep",
        "EX_BLOG_CLASSIFIER_MODEL" => "test/classifier",
        "EX_BLOG_MCP_TOKEN" => "test-mcp-token",
        "EX_BLOG_DATA_DIR" => Path.expand("../../tmp", __DIR__)
      })

    struct!(base, overrides)
  end

  defp build(env) do
    supported_result = languages(env)

    default_result =
      case supported_result do
        {:ok, supported} -> default_language(env, supported)
        {:error, _reason} -> {:ok, optional(env, "EX_BLOG_DEFAULT_LANGUAGE") || "it"}
      end

    validations = [
      admin_password_hash: password_hash(env),
      admin_telegram_id: positive_integer(env, "EX_BLOG_ADMIN_TELEGRAM_ID"),
      telegram_api_id: positive_integer(env, "EX_BLOG_TELEGRAM_API_ID"),
      telegram_session_id: telegram_session_id(env),
      github_repository: repository(env),
      supported_languages: supported_result,
      default_language: default_result,
      monthly_budget_eur: positive_decimal(env, "EX_BLOG_MONTHLY_BUDGET_EUR", "20"),
      max_article_cost_eur: positive_decimal(env, "EX_BLOG_MAX_ARTICLE_COST_EUR", "2"),
      usd_eur_rate: positive_decimal(env, "EX_BLOG_USD_EUR_RATE", "0.92"),
      embedding_dimensions: positive_integer(env, "EX_BLOG_EMBEDDING_DIMENSIONS", "1024"),
      git_sync_interval_ms: positive_integer(env, "EX_BLOG_GIT_SYNC_INTERVAL_MS", "900000"),
      data_dir: absolute_path(env),
      content_root: content_root(env)
    ]

    errors =
      for {_field, {:error, error}} <- validations do
        error
      end

    if errors == [] do
      values = Map.new(validations, fn {field, {:ok, value}} -> {field, value} end)

      {:ok,
       %__MODULE__{
         admin_password_hash: values.admin_password_hash,
         admin_telegram_id: values.admin_telegram_id,
         admin_telegram_username: optional(env, "EX_BLOG_ADMIN_TELEGRAM_USERNAME"),
         github_repository: values.github_repository,
         github_branch: value(env, "EX_BLOG_GITHUB_BRANCH"),
         fast_model: value(env, "EX_BLOG_LLM_FAST_MODEL"),
         balanced_model: value(env, "EX_BLOG_LLM_BALANCED_MODEL"),
         deep_model: value(env, "EX_BLOG_LLM_DEEP_MODEL"),
         classifier_model: value(env, "EX_BLOG_CLASSIFIER_MODEL"),
         embedding_model:
           optional(env, "EX_BLOG_EMBEDDING_MODEL") ||
             "openrouter:perplexity/pplx-embed-v1-0.6b",
         embedding_dimensions: values.embedding_dimensions,
         default_language: values.default_language,
         supported_languages: values.supported_languages,
         monthly_budget_eur: values.monthly_budget_eur,
         max_article_cost_eur: values.max_article_cost_eur,
         usd_eur_rate: values.usd_eur_rate,
         github_author_name: optional(env, "EX_BLOG_GITHUB_AUTHOR_NAME") || "ExBlog Agent",
         github_author_email:
           optional(env, "EX_BLOG_GITHUB_AUTHOR_EMAIL") ||
             "ex-blog@users.noreply.github.com",
         data_dir: values.data_dir,
         content_root: values.content_root,
         git_sync_interval_ms: values.git_sync_interval_ms,
         telegram_api_id: values.telegram_api_id,
         telegram_session_id: values.telegram_session_id,
         phx_host: optional(env, "PHX_HOST"),
         github_token: value(env, "EX_BLOG_GITHUB_TOKEN"),
         openrouter_api_key: value(env, "OPENROUTER_API_KEY"),
         telegram_api_hash: value(env, "EX_BLOG_TELEGRAM_API_HASH"),
         mcp_token: value(env, "EX_BLOG_MCP_TOKEN")
       }}
    else
      {:error, format_errors([], errors)}
    end
  end

  defp positive_integer(env, name, default \\ nil) do
    raw = optional(env, name) || default

    case Integer.parse(raw || "") do
      {value, ""} when value > 0 -> {:ok, value}
      _other -> {:error, {name, "must be a positive integer"}}
    end
  end

  defp positive_decimal(env, name, default) do
    case Decimal.parse(optional(env, name) || default) do
      {value, ""} ->
        if Decimal.positive?(value),
          do: {:ok, value},
          else: {:error, {name, "must be a positive number"}}

      _other ->
        {:error, {name, "must be a positive number"}}
    end
  end

  defp repository(env) do
    repository = value(env, "EX_BLOG_GITHUB_REPOSITORY")

    if Regex.match?(~r/^[\w.-]+\/[\w.-]+$/u, repository) do
      {:ok, repository}
    else
      {:error, {"EX_BLOG_GITHUB_REPOSITORY", "must use the owner/repository format"}}
    end
  end

  defp telegram_session_id(env) do
    session_id = optional(env, "EX_BLOG_TELEGRAM_SESSION_ID") || "ex_blog"

    if Regex.match?(~r/^[A-Za-z0-9_-]+$/u, session_id) do
      {:ok, session_id}
    else
      {:error,
       {"EX_BLOG_TELEGRAM_SESSION_ID",
        "must contain only letters, numbers, underscores, or hyphens"}}
    end
  end

  defp password_hash(env) do
    hash = value(env, "EX_BLOG_ADMIN_PASSWORD_HASH")

    if String.starts_with?(hash, ["$argon2id$", "$argon2i$", "$argon2d$"]) do
      {:ok, hash}
    else
      {:error, {"EX_BLOG_ADMIN_PASSWORD_HASH", "must be an Argon2 encoded hash"}}
    end
  end

  defp languages(env) do
    languages =
      env
      |> optional("EX_BLOG_SUPPORTED_LANGUAGES")
      |> Kernel.||("it,en")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if languages != [] and Enum.all?(languages, &Regex.match?(~r/^[a-z]{2}(?:-[A-Z]{2})?$/, &1)) do
      {:ok, languages}
    else
      {:error,
       {"EX_BLOG_SUPPORTED_LANGUAGES", "must be a comma-separated list of language codes"}}
    end
  end

  defp default_language(env, supported) do
    language = optional(env, "EX_BLOG_DEFAULT_LANGUAGE") || "it"

    if language in supported do
      {:ok, language}
    else
      {:error, {"EX_BLOG_DEFAULT_LANGUAGE", "must be included in EX_BLOG_SUPPORTED_LANGUAGES"}}
    end
  end

  defp absolute_path(env) do
    path = optional(env, "EX_BLOG_DATA_DIR") || "/data"

    if Path.type(path) == :absolute do
      {:ok, Path.expand(path)}
    else
      {:error, {"EX_BLOG_DATA_DIR", "must be an absolute path"}}
    end
  end

  defp content_root(env) do
    root = optional(env, "EX_BLOG_CONTENT_ROOT") || "content"
    segments = Path.split(root)

    if Path.type(root) == :relative and root not in ["", "."] and
         Enum.all?(segments, &(&1 not in ["..", ".", "/"])) do
      {:ok, Path.join(segments)}
    else
      {:error, {"EX_BLOG_CONTENT_ROOT", "must be a safe relative directory"}}
    end
  end

  defp format_errors(missing, invalid) do
    sections =
      []
      |> maybe_missing(missing)
      |> maybe_invalid(invalid)

    "ExBlog cannot start.\n\n" <> Enum.join(sections, "\n\n")
  end

  defp maybe_missing(sections, []), do: sections

  defp maybe_missing(sections, missing) do
    sections ++
      ["Missing required environment variables:\n" <> Enum.map_join(missing, "\n", &"- #{&1}")]
  end

  defp maybe_invalid(sections, []), do: sections

  defp maybe_invalid(sections, invalid) do
    sections ++
      [
        "Invalid environment variables:\n" <>
          Enum.map_join(invalid, "\n", fn {name, reason} -> "- #{name}: #{reason}" end)
      ]
  end

  defp optional(env, name) do
    case Map.get(env, name) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _other ->
        nil
    end
  end

  defp value(env, name), do: optional(env, name) || ""
  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end
