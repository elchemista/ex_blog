defmodule ExBlog.Agent.SemanticCache do
  @moduledoc """
  Durable adapter for Spectre's learned semantic route cache.

  This is a routing cache, not conversational memory. The row value is an
  intent label plus routing evidence; article bodies, model prompts, and action
  arguments are never stored here. Spectre owns row validation, Vettore search,
  route visibility, and the review lifecycle. This adapter adds two application
  guarantees:

  * online rows and their embeddings are snapshotted to the DETS runtime store;
  * an unreviewed row can become verified without an admin UI only when a later
    query exceeds both the very-high similarity and label-margin gates.

  Policy-protected mutations are never learned by Spectre, and ExBlog only
  marks explicitly learnable read routes for online learning. Semantic
  verification therefore cannot approve or execute a repository mutation.

  A normal learned route moves through these states:

      LLM classifies a learnable read intent
      -> Spectre stores its text and embedding as unverified
      -> an exact repeat or exceptionally close paraphrase reuses the row
      -> the adapter verifies it only after the similarity and margin gates
      -> future paraphrases can match the verified vector at the search gate

  The online ETS/Vettore structures remain replaceable caches. DETS snapshots
  make reviewed rows survive deploys, and `restore/1` rebuilds Spectre's online
  store during application startup.
  """

  use GenServer

  @behaviour Spectre.Router.SemanticCache

  require Logger

  alias ExBlog.Agent.ClassifierConfig
  alias ExBlog.Storage
  alias Spectre.Router.SemanticCache, as: Cache
  alias Spectre.Router.SemanticCache.Learned
  alias Spectre.Router.SemanticCache.Learned.Index

  @default_search_threshold 0.94
  @default_auto_verify_threshold 0.985
  @default_auto_verify_margin 0.05

  @doc "Starts the adapter and restores the persisted snapshot before serving lookups."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    case restore() do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("semantic_cache restore_failed reason=#{inspect(reason)}")
    end

    case warm() do
      {:ok, vectors} ->
        Logger.info("semantic_cache warm_ready vectors=#{vectors}")

      {:error, reason} ->
        Logger.warning("semantic_cache warm_failed reason=#{inspect(reason)}")
    end

    {:ok, %{}}
  end

  @impl Cache
  def lookup(text, opts) when is_binary(text) and is_list(opts) do
    # Exact lookup and vector lookup share the Spectre adapter callback. The
    # semantic-search plug sets `:semantic_search?` explicitly for vector work.
    opts = runtime_opts(opts)

    case Learned.lookup_with_metadata(text, search_opts(opts)) do
      {:ok, result, _metadata} ->
        {:ok, result}

      {:error, reason, _metadata} ->
        maybe_auto_verify(text, reason, opts)
    end
  end

  @impl Cache
  def put(text, result, opts) do
    # Learned.put acquires the embedding once and stores it on the row. Search
    # later embeds only the incoming query; it never re-embeds the row dataset.
    opts = runtime_opts(opts)

    with {:ok, row} <- Learned.put(text, result, opts),
         :ok <- persist(row.agent, opts) do
      {:ok, row}
    end
  end

  @impl Cache
  def examples(agent, opts), do: Learned.examples(agent, runtime_opts(agent, opts))

  @impl Cache
  def get_example(agent, id, opts),
    do: Learned.get_example(agent, id, runtime_opts(agent, opts))

  @impl Cache
  def relabel(agent, id, label, opts) do
    opts = runtime_opts(agent, opts)

    with {:ok, row} <- Learned.relabel(agent, id, label, opts),
         :ok <- persist(agent, opts) do
      {:ok, row}
    end
  end

  @impl Cache
  def update_example(agent, id, attrs, opts) do
    opts = runtime_opts(agent, opts)

    with {:ok, row} <- Learned.update_example(agent, id, attrs, opts),
         :ok <- persist(agent, opts) do
      {:ok, row}
    end
  end

  @impl Cache
  def delete(agent, id, opts) do
    opts = runtime_opts(agent, opts)

    with :ok <- Learned.delete(agent, id, opts) do
      persist(agent, opts)
    end
  end

  @impl Cache
  def verify(agent, id, opts) do
    opts = runtime_opts(agent, opts)

    with {:ok, row} <- Learned.verify(agent, id, opts),
         :ok <- persist(agent, opts) do
      {:ok, row}
    end
  end

  @impl Cache
  def snapshot(agent, opts), do: Learned.snapshot(agent, runtime_opts(agent, opts))

  @impl Cache
  def load_snapshot(agent, snapshot, opts) do
    opts = runtime_opts(agent, opts)

    with {:ok, summary} <- Learned.load_snapshot(agent, snapshot, opts),
         :ok <- persist(agent, opts) do
      {:ok, summary}
    end
  end

  @impl Cache
  def clear(agent, opts) do
    with :ok <- Learned.clear(agent, runtime_opts(agent, opts)) do
      Storage.delete(storage_key(agent))
    end
  end

  @doc "Restores one agent's online semantic rows from the durable DETS snapshot."
  @spec restore(module()) :: :ok | {:error, term()}
  def restore(agent \\ ExBlog.Agent) when is_atom(agent) do
    case Storage.fetch(storage_key(agent)) do
      :error ->
        :ok

      {:ok, rows} when is_list(rows) ->
        case Learned.load_snapshot(agent, rows, runtime_opts(agent, [])) do
          {:ok, _summary} -> :ok
          {:error, _reason} = error -> error
        end

      {:ok, _invalid} ->
        {:error, :invalid_semantic_cache_snapshot}
    end
  end

  @doc "Builds the Vettore projection from stored offline and online vectors."
  @spec warm(module()) :: {:ok, non_neg_integer()} | {:error, term()}
  def warm(agent \\ ExBlog.Agent) when is_atom(agent) do
    opts = runtime_opts(agent, [])

    with {:ok, rows} <- Learned.rows(opts), do: Index.warm(rows, opts)
  end

  defp maybe_auto_verify(text, original_reason, opts) do
    if Keyword.get(opts, :semantic_search?, false) do
      verify_semantic_match(text, original_reason, opts)
    else
      {:error, original_reason}
    end
  end

  defp verify_semantic_match(text, original_reason, opts) do
    # Normal semantic search excludes unverified rows. This second, stricter
    # search includes them solely to decide whether one row is safe to promote.
    review_opts =
      opts
      |> Keyword.put(:semantic_cache_include_unverified?, true)
      |> Keyword.put(:semantic_cache_threshold, auto_verify_threshold())

    with {:ok, result, _metadata} <- Learned.lookup_with_metadata(text, review_opts),
         true <- high_confidence?(result),
         {:ok, row} <- unverified_source_row(result),
         :ok <- learnable_row(row, opts),
         {:ok, _verified} <- Learned.verify(row.agent, row.id, opts),
         :ok <- persist(row.agent, opts) do
      {:ok,
       Map.update(result, :metadata, %{auto_verified?: true}, fn metadata ->
         Map.put(metadata || %{}, :auto_verified?, true)
       end)}
    else
      false -> {:error, original_reason}
      {:error, _reason, _metadata} -> {:error, original_reason}
      {:error, _reason} -> {:error, original_reason}
      {:skip, _reason} -> {:error, original_reason}
    end
  end

  defp high_confidence?(result) do
    # Similarity alone is insufficient: a near tie between two labels remains
    # ambiguous even when the top vector is individually very close.
    score = Map.get(result, :confidence, 0.0)
    label = Map.get(result, :label)

    competing_score =
      result
      |> Map.get(:scores, %{})
      |> Enum.reject(fn {candidate, _score} -> same_label?(candidate, label) end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.max(fn -> 0.0 end)

    is_number(score) and score >= auto_verify_threshold() and
      score - competing_score >= auto_verify_margin()
  end

  defp unverified_source_row(%{semantic_examples: [row | _rest]}) do
    if Map.get(row, :source) == :online_learned and Map.get(row, :verified?) == false,
      do: {:ok, row},
      else: {:error, :semantic_row_not_reviewable}
  end

  defp unverified_source_row(_result), do: {:error, :semantic_row_missing}

  defp learnable_row(row, opts) do
    rule = Enum.find(Keyword.get(opts, :spectre_rules, []), &(&1.label == row.label))

    route = %{
      label: row.label,
      accepted?: true,
      strategy: row.source_strategy,
      handler: rule && rule.handler
    }

    Cache.learn_eligibility(row.agent, route)
  end

  defp persist(agent, opts) do
    # Snapshot rows include their embeddings, so restore does not need to call
    # OpenRouter or rebuild vectors from raw text.
    case Learned.snapshot(agent, Keyword.put(runtime_opts(agent, opts), :source, :online_learned)) do
      {:ok, rows} -> Storage.put(storage_key(agent), rows)
      {:error, _reason} = error -> error
    end
  end

  defp search_opts(opts) do
    if Keyword.get(opts, :semantic_search?, false) do
      Keyword.put(opts, :semantic_cache_threshold, search_threshold())
    else
      opts
    end
  end

  defp runtime_opts(opts) do
    agent =
      case Keyword.get(opts, :spectre_agent) do
        agent when is_atom(agent) and not is_nil(agent) -> agent
        _missing -> ExBlog.Agent
      end

    runtime_opts(agent, opts)
  end

  defp runtime_opts(agent, opts) do
    # Adapter callbacks may arrive with only per-call options. Rebuilding the
    # compiled rule set here preserves route visibility and cacheability checks
    # for direct review operations as well as normal router calls.
    rules =
      agent
      |> Spectre.Definition.rules()
      |> Enum.map(&Spectre.Rule.new/1)

    agent.__spectre_router__()
    |> Keyword.merge(opts)
    |> Keyword.put(:spectre_agent, agent)
    |> Keyword.put(:spectre_rules, rules)
  end

  defp search_threshold,
    do: semantic_setting(:search_threshold, @default_search_threshold)

  defp auto_verify_threshold,
    do: semantic_setting(:auto_verify_threshold, @default_auto_verify_threshold)

  defp auto_verify_margin,
    do: semantic_setting(:auto_verify_margin, @default_auto_verify_margin)

  defp semantic_setting(key, default) do
    :ex_blog
    |> Application.get_env(:semantic_cache, [])
    |> Keyword.get(key, default)
  end

  defp same_label?(left, right) do
    String.upcase(to_string(left)) == String.upcase(to_string(right))
  end

  defp storage_key(agent) do
    {
      :spectre_semantic_cache,
      inspect(agent),
      ClassifierConfig.encoder_model()
    }
  end
end
