defmodule ExBlog.Agent.SemanticCacheTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Agent
  alias ExBlog.Agent.SemanticCache
  alias ExBlog.AI.Embedding
  alias Spectre.Router.SemanticCache, as: Cache
  alias Spectre.Router.SemanticCache.Learned

  setup do
    :ok = Cache.clear(Agent)
    on_exit(fn -> Cache.clear(Agent) end)
    :ok
  end

  test "a very-high semantic match auto-verifies and persists an online example" do
    opts = semantic_opts(&article_embedding/2)

    assert {:ok, learned} =
             Cache.put(
               "show me every published article",
               %{
                 label: :LIST_ARTICLES,
                 accepted?: true,
                 confidence: 0.86,
                 source_strategy: :llm_classifier
               },
               opts
             )

    refute learned.verified?

    assert {:error, :miss} =
             Cache.lookup(
               "show me all published blog articles",
               Keyword.put(opts, :semantic_search?, false)
             )

    assert {:ok, result} =
             Cache.lookup(
               "show me all published blog articles",
               Keyword.put(opts, :semantic_search?, true)
             )

    assert result.label == :LIST_ARTICLES
    assert result.confidence >= 0.985
    assert result.metadata.auto_verified?

    assert {:ok, verified} = Cache.get_example(Agent, learned.id, opts)
    assert verified.verified?

    :ok = Learned.clear(Agent, opts)
    assert {:error, :not_found} = Learned.get_example(Agent, learned.id, opts)

    assert :ok = SemanticCache.restore(Agent, opts)
    assert {:ok, restored} = Cache.get_example(Agent, learned.id, opts)
    assert restored.verified?
    assert restored.embedding == [1.0, 0.0]
  end

  test "a low-similarity query cannot promote an unverified example" do
    opts = semantic_opts(&article_embedding/2)

    assert {:ok, learned} =
             Cache.put(
               "show me every published article",
               %{
                 label: :LIST_ARTICLES,
                 accepted?: true,
                 confidence: 0.86,
                 source_strategy: :llm_classifier
               },
               opts
             )

    assert {:error, :semantic_cache_embeddings_not_loaded} =
             Cache.lookup("find posts about Elixir", Keyword.put(opts, :semantic_search?, true))

    assert {:ok, unchanged} = Cache.get_example(Agent, learned.id, opts)
    refute unchanged.verified?
  end

  defp semantic_opts(embedding_fun) do
    rules =
      Agent
      |> Spectre.Definition.rules()
      |> Enum.map(&Spectre.Rule.new/1)

    Agent.__spectre_router__()
    |> Keyword.put(:spectre_agent, Agent)
    |> Keyword.put(:spectre_rules, rules)
    |> Keyword.put(:embedding, {
      Embedding,
      [embedding_dimensions: 2, embedding_fun: embedding_fun]
    })
  end

  defp article_embedding(text, _opts) do
    vector =
      if String.contains?(String.downcase(text), ["all", "every"]),
        do: [1.0, 0.0],
        else: [0.0, 1.0]

    {:ok, vector}
  end
end
