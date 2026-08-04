defmodule ExBlog.Agent.RouterPipeline do
  @moduledoc """
  Evidence-first Spectre routing for the editorial agent.

  The ordering combines Spectre's trained routing providers with ExBlog's
  deterministic article-intake cursor:

    * safety and cancellation interrupts are hard regex evidence;
    * an active nested flow owns its current free-text answer;
    * the learned cache gets an exact lookup before any embedding call;
    * an optional development/test classifier can handle known paraphrases
      without a network request;
    * optional static skill embeddings and learned semantic search add further
      probabilistic evidence;
    * arbitration invokes the configured LLM classifier when no candidate is
      strong enough or providers conflict.

  A route's explicit `via:` list still controls which providers may see it.
  Editorial mutations expose embeddings and both classifiers for natural
  language understanding, but never opt into learned semantic-cache routing.

  The agent's production `via:` list enables learned semantic search but leaves
  static embedding similarity off. The learned index needs one query embedding,
  whereas the stock static matcher embeds every route example during a request.
  A caller can still opt into `via: [:embedding]` for evaluation or when an
  additional cache makes that cost appropriate.
  """

  alias ExBlog.Agent.Router.Plugs.CreationContinuation
  alias Spectre.Router.Context

  @strategy_plugs %{
    regex: [Spectre.Router.Plugs.Regex],
    embedding: [Spectre.Router.Plugs.EmbeddingSimilarity],
    classifier: [Spectre.Router.Plugs.LocalClassifier]
  }

  @spec call(Context.t()) :: {:ok, Context.t()} | {:error, term()}
  def call(%Context{} = context) do
    via = effective_via(context)

    # Ordering is part of the safety and cost model. Hard regex evidence stops
    # model-backed providers; the active creation cursor then claims free text;
    # exact cache runs before model work; the trained classifier precedes
    # broader semantic search; arbitration is the only place allowed to invoke
    # the remote LLM classifier.
    specs =
      [:regex]
      |> enabled_plugs(via)
      |> Kernel.++([CreationContinuation])
      |> Kernel.++(semantic_exact_plugs(via))
      |> Kernel.++(enabled_plugs([:embedding, :classifier], via))
      |> Kernel.++(semantic_search_plugs(via))
      |> Kernel.++([
        Spectre.Router.Plugs.Arbitrate,
        Spectre.Router.Plugs.Terminalize
      ])

    Spectre.Pipeline.run(context, specs)
  end

  @spec effective_via(Context.t()) :: [atom()]
  defp effective_via(%Context{opts: opts, rules: rules}) do
    via = opts |> Keyword.get(:via, [:regex]) |> List.wrap()

    if semantic_cache_enabled?(opts, rules) do
      Enum.uniq(via ++ [:semantic_cache])
    else
      Enum.reject(via, &(&1 == :semantic_cache))
    end
  end

  @spec semantic_cache_enabled?(keyword(), [Spectre.Rule.t()]) :: boolean()
  defp semantic_cache_enabled?(opts, rules) do
    Keyword.get(opts, :semantic_cache?, true) and Enum.any?(rules, & &1.cache)
  end

  @spec enabled_plugs([atom()], [atom()]) :: [module()]
  defp enabled_plugs(strategies, via) do
    strategies
    |> Enum.filter(&(&1 in via))
    |> Enum.flat_map(&Map.fetch!(@strategy_plugs, &1))
  end

  @spec semantic_exact_plugs([atom()]) :: [module()]
  defp semantic_exact_plugs(via) do
    if :semantic_cache in via, do: [Spectre.Router.Plugs.SemanticCacheExact], else: []
  end

  @spec semantic_search_plugs([atom()]) :: [module()]
  defp semantic_search_plugs(via) do
    if :semantic_cache in via, do: [Spectre.Router.Plugs.SemanticCacheSearch], else: []
  end
end
