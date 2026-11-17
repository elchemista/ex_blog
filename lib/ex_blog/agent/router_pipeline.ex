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
  static embedding similarity off. The learned index needs one query embedding.
  Spectre 0.4 caches static route-example vectors; their first use and later
  cache misses can still require encoding. A caller can opt into
  `via: [:embedding]` when that recognition strategy suits the application.
  """

  alias ExBlog.Agent.Router.Plugs.CreationContinuation
  alias Spectre.Router.Context

  @strategy_plugs %{
    regex: [Spectre.Router.Plugs.Regex],
    embedding: [Spectre.Router.Plugs.EmbeddingSimilarity],
    classifier: [Spectre.Router.Plugs.LocalClassifier]
  }

  @doc "Whether the pipeline exposes its closed model-free evaluation mode."
  @spec rehearsable?() :: boolean()
  def rehearsable?, do: true

  @doc """
  Runs a synchronous Morph rehearsal without consulting models or learned routes.

  The scoped marker follows Spectre's protected provider workers through their
  OTP caller chain and is restored even when the checker raises.
  """
  @spec rehearse((-> result)) :: result when result: var
  def rehearse(fun) when is_function(fun, 0) do
    previous = Process.put(__MODULE__, :rehearsal)

    try do
      fun.()
    after
      if previous, do: Process.put(__MODULE__, previous), else: Process.delete(__MODULE__)
    end
  end

  @spec call(Context.t()) :: {:ok, Context.t()} | {:error, term()}
  def call(%Context{} = context) do
    if rehearsal?() do
      evaluation_call(context)
    else
      live_call(context)
    end
  end

  @spec rehearsal?() :: boolean()
  defp rehearsal? do
    Enum.any?([self() | Process.get(:"$callers", [])], fn caller ->
      node(caller) == node() and
        Process.info(caller, {:dictionary, __MODULE__}) == {{:dictionary, __MODULE__}, :rehearsal}
    end)
  end

  defp live_call(context) do
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

  # Governance replay must never sample a model, learned cache, hosted
  # embedding, or stateful continuation. Only the scoped Morph checker enters
  # this branch; ordinary `Spectre.Router.evaluate/3` observes the live routing
  # providers without executing their selected handler.
  defp evaluation_call(context) do
    opts =
      context.opts
      |> Keyword.put(:via, [:regex])
      |> Keyword.put(:semantic_cache?, false)
      |> Keyword.put(:llm_classifier?, false)

    context = %{context | opts: opts}

    Spectre.Pipeline.run(context, [
      Spectre.Router.Plugs.Regex,
      Spectre.Router.Plugs.Arbitrate,
      Spectre.Router.Plugs.Terminalize
    ])
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
