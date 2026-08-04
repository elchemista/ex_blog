defmodule ExBlog.ConfigTest do
  use ExUnit.Case, async: true

  alias ExBlog.Config

  test "reports every missing variable in one redaction-safe error" do
    assert {:error, message} = Config.load(%{})

    assert message =~ "ExBlog cannot start."
    assert message =~ "Missing required environment variables:"

    for name <- Config.required_env_names() do
      assert message =~ "- #{name}"
    end
  end

  test "production includes Phoenix deployment requirements" do
    env = full_env() |> Map.drop(["SECRET_KEY_BASE", "PHX_HOST"])

    assert {:error, message} = Config.load(env, production?: true)
    assert message =~ "- SECRET_KEY_BASE"
    assert message =~ "- PHX_HOST"
  end

  test "requires the Telegram username instead of a numeric administrator ID" do
    required = Config.required_env_names()

    assert "EX_BLOG_ADMIN_TELEGRAM_USERNAME" in required
    refute "EX_BLOG_ADMIN_TELEGRAM_ID" in required

    env = Map.put(full_env(), "EX_BLOG_ADMIN_TELEGRAM_ID", "123456789")

    assert {:ok, config} = Config.load(env)
    assert config.admin_telegram_username == "editorial_admin"
  end

  test "aggregates invalid typed values" do
    env =
      full_env()
      |> Map.put("EX_BLOG_ADMIN_PASSWORD_HASH", "not-an-argon2-hash")
      |> Map.put("EX_BLOG_ADMIN_TELEGRAM_USERNAME", "not a username")
      |> Map.put("TG_API_ID", "not-an-id")
      |> Map.put("EX_BLOG_TELEGRAM_SESSION_ID", "../unsafe")
      |> Map.put("EX_BLOG_GITHUB_REPOSITORY", "not a repository")
      |> Map.put("EX_BLOG_MONTHLY_BUDGET_EUR", "-1")
      |> Map.put("EX_BLOG_EMBEDDING_DIMENSIONS", "0")
      |> Map.put("EX_BLOG_GIT_SYNC_INTERVAL_MS", "0")

    assert {:error, message} = Config.load(env)
    assert message =~ "EX_BLOG_ADMIN_PASSWORD_HASH: must be an Argon2 encoded hash"
    assert message =~ "EX_BLOG_ADMIN_TELEGRAM_USERNAME: must be a Telegram username"
    assert message =~ "TG_API_ID: must be a positive integer"
    assert message =~ "EX_BLOG_TELEGRAM_SESSION_ID"
    assert message =~ "EX_BLOG_GITHUB_REPOSITORY: must use the owner/repository format"
    assert message =~ "EX_BLOG_MONTHLY_BUDGET_EUR: must be a positive number"
    assert message =~ "EX_BLOG_EMBEDDING_DIMENSIONS: must be a positive integer"
    assert message =~ "EX_BLOG_GIT_SYNC_INTERVAL_MS: must be a positive integer"
  end

  test "builds a safe public projection without credential values" do
    assert {:ok, config} = Config.load(full_env())

    output = inspect(Config.public(config))
    inspected_config = inspect(config)

    refute output =~ "github-secret-value"
    refute output =~ "argon2id"
    refute output =~ "openrouter-secret-value"
    refute output =~ "telegram-api-secret-value"
    refute output =~ "mcp-secret-value"

    refute inspected_config =~ "github-secret-value"
    refute inspected_config =~ "openrouter-secret-value"
    assert Config.public(config).github_token == :configured
    assert Config.public(config).openrouter_token == :configured
    assert Config.public(config).agent_language == "en"

    assert Config.public(config).models.embedding ==
             "openrouter:perplexity/pplx-embed-v1-0.6b"

    assert Config.public(config).models.local_classifier ==
             "intfloat/multilingual-e5-small"

    assert Config.public(config).models.routing_embedding ==
             "local:intfloat/multilingual-e5-small"

    assert config.embedding_dimensions == 1024
  end

  test "normalizes the administrator Telegram username" do
    env = Map.put(full_env(), "EX_BLOG_ADMIN_TELEGRAM_USERNAME", "  @Editorial_Admin  ")

    assert {:ok, config} = Config.load(env)
    assert config.admin_telegram_username == "editorial_admin"
  end

  test "accepts the legacy ExBlog-prefixed Telegram credential aliases" do
    env =
      full_env()
      |> Map.delete("TG_API_ID")
      |> Map.delete("TG_API_HASH")
      |> Map.put("EX_BLOG_TELEGRAM_API_ID", "54321")
      |> Map.put("EX_BLOG_TELEGRAM_API_HASH", "legacy-telegram-secret")

    assert {:ok, config} = Config.load(env)
    assert config.telegram_api_id == 54_321
    assert config.telegram_api_hash == "legacy-telegram-secret"
  end

  test "redacts every configured credential from arbitrary text" do
    config = Config.load!(full_env())

    text =
      "$argon2id$admin-password-hash github-secret-value openrouter-secret-value " <>
        "telegram-api-secret-value mcp-secret-value"

    assert Config.redact(text, config) ==
             "[REDACTED] [REDACTED] [REDACTED] [REDACTED] [REDACTED]"
  end

  test "validates language membership and safe content paths" do
    env =
      full_env()
      |> Map.put("EX_BLOG_DEFAULT_LANGUAGE", "fr")
      |> Map.put("EX_BLOG_SUPPORTED_LANGUAGES", "it,en")
      |> Map.put("EX_BLOG_CONTENT_ROOT", "../outside")

    assert {:error, message} = Config.load(env)
    assert message =~ "EX_BLOG_DEFAULT_LANGUAGE"
    assert message =~ "EX_BLOG_CONTENT_ROOT"
  end

  defp full_env do
    %{
      "EX_BLOG_ADMIN_PASSWORD_HASH" => "$argon2id$admin-password-hash",
      "EX_BLOG_ADMIN_TELEGRAM_USERNAME" => "editorial_admin",
      "TG_API_ID" => "12345",
      "TG_API_HASH" => "telegram-api-secret-value",
      "EX_BLOG_GITHUB_TOKEN" => "github-secret-value",
      "EX_BLOG_GITHUB_REPOSITORY" => "elchemista/ex-blog-content",
      "EX_BLOG_GITHUB_BRANCH" => "main",
      "OPENROUTER_API_KEY" => "openrouter-secret-value",
      "EX_BLOG_LLM_FAST_MODEL" => "openai/fast",
      "EX_BLOG_LLM_BALANCED_MODEL" => "openai/balanced",
      "EX_BLOG_LLM_DEEP_MODEL" => "openai/deep",
      "EX_BLOG_CLASSIFIER_MODEL" => "openai/classifier",
      "EX_BLOG_MCP_TOKEN" => "mcp-secret-value",
      "EX_BLOG_DATA_DIR" => "/data",
      "SECRET_KEY_BASE" => String.duplicate("s", 64),
      "PHX_HOST" => "blog.example.com"
    }
  end
end
