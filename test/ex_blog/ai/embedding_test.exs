defmodule ExBlog.AI.EmbeddingTest do
  use ExUnit.Case, async: true

  alias ExBlog.AI.Embedding

  test "uses the configured Freelance-compatible OpenRouter contract" do
    test_pid = self()

    embedding_fun = fn text, opts ->
      send(test_pid, {:embedding_request, text, opts})
      {:ok, List.duplicate(0.25, 1024)}
    end

    assert {:ok, vector} = Embedding.embed("list the articles", embedding_fun: embedding_fun)
    assert length(vector) == 1024

    assert_receive {:embedding_request, "list the articles", opts}
    assert opts[:model] == "perplexity/pplx-embed-v1-0.6b"
    assert opts[:dimensions] == 1024
    assert opts[:encoding_format] == "float"
    assert opts[:transport] == ExBlog.AI.Transport
    assert opts[:purpose] == :semantic_cache_embedding
  end

  test "rejects a provider vector with incompatible dimensions" do
    embedding_fun = fn _text, _opts -> {:ok, [0.1, 0.2]} end

    assert {:error, {:embedding_dimension_mismatch, 1024, 2}} =
             Embedding.embed("wrong size", embedding_fun: embedding_fun)
  end

  test "redacts credentials before requesting an embedding" do
    secret = ExBlog.Config.fetch_secret!(:openrouter_api_key)
    test_pid = self()

    embedding_fun = fn text, _opts ->
      send(test_pid, {:embedded_text, text})
      {:ok, List.duplicate(0.0, 1024)}
    end

    assert {:ok, _vector} =
             Embedding.embed("route #{secret}", embedding_fun: embedding_fun)

    assert_receive {:embedded_text, "route [REDACTED]"}
  end
end
