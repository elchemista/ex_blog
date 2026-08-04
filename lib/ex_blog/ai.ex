defmodule ExBlog.AI do
  @moduledoc """
  Spectre Stack composition and direct AI boundary for ExBlog.

  The Stack gives agent code stable capability names while deployment config
  chooses concrete OpenRouter models at runtime. Prism selects a tier by
  purpose, Beam normalizes Telegram delivery, and Kinetic validates typed
  actions. None of those extensions owns editorial business logic; they are
  infrastructure mounted around `ExBlog.Agent`.

  Direct helpers such as `complete/3` and `health/1` exist for bounded leaf
  operations that do not need a full Spectre reasoning turn. They still use the
  same transport, credentials, budget authorization, and usage accounting.
  """

  use Spectre.Stack, id: :ex_blog

  alias ExBlog.AI.OpenRouter
  alias ExBlog.Config

  require OpenRouter

  # Stable markers are compiled into the Stack. OpenRouter resolves them to the
  # environment's current model ids at call time, so builds contain no secrets.
  install Spectre.Prism, max_attempts: 2 do
    provider(:openrouter, OpenRouter,
      models: [
        fast: "ex-blog/runtime-fast",
        balanced: "ex-blog/runtime-balanced",
        deep: "ex-blog/runtime-deep"
      ],
      classifier: :fast,
      embedding: [model: "ex-blog/runtime-embedding", dimensions: 1024]
    )

    purpose(:route_classification, prefer: :fast)
    purpose(:response_generation, prefer: :balanced)
    purpose(:category_generation, prefer: :fast)
    purpose(:title_generation, prefer: :balanced)
    purpose(:seo_generation, prefer: :balanced)
    purpose(:article_generation, prefer: :deep)
    purpose(:page_audit, prefer: :balanced)
    default(:balanced)
  end

  # Delivery is caller-owned because the Telegram gateway must acknowledge and
  # format results after Spectre finishes the turn.
  install Spectre.Beam, delivery: :caller_owned do
    channel(:telegram,
      type: :telegram,
      adapter: Spectre.Beam.Adapters.ExGram,
      capabilities: [:text, :image],
      planner_exposure: :none,
      typing: true
    )
  end

  # Kinetic receives a single best typed action. Policy enforcement remains in
  # Spectre Agent and is intentionally not delegated to the planner.
  install(Spectre.Kinetic,
    top_k: 1,
    tool_threshold: 0.0,
    mapping_threshold: 0.0
  )

  @doc "Completes one bounded prompt through the configured Prism model tier."
  @spec complete(:fast | :balanced | :deep, String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def complete(level, prompt, opts \\ []) when level in [:fast, :balanced, :deep] do
    opts = Keyword.put(opts, :model, OpenRouter.marker(level))
    OpenRouter.complete(prompt, opts)
  end

  @doc "Checks OpenRouter and confirms that every configured text model is advertised."
  @spec health(keyword()) :: {:ok, map()} | {:error, term()}
  def health(opts \\ []) do
    config = Config.get()
    url = Keyword.get(opts, :url, "https://openrouter.ai/api/v1/models")

    request_options =
      [
        url: url,
        headers: [{"authorization", "Bearer #{Config.fetch_secret!(:openrouter_api_key)}"}],
        receive_timeout: 15_000,
        retry: false
      ]
      |> Keyword.merge(Keyword.get(opts, :req_options, []))

    case Req.get(request_options) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        available = model_ids(body)

        configured = [
          config.fast_model,
          config.balanced_model,
          config.deep_model,
          config.classifier_model
        ]

        {:ok,
         %{
           configured: true,
           reachable: true,
           models_available: Enum.all?(configured, &MapSet.member?(available, &1))
         }}

      {:ok, %{status: status}} ->
        {:error, {:openrouter_http_error, status}}

      {:error, reason} ->
        {:error, {:openrouter_unreachable, reason}}
    end
  end

  defp model_ids(%{"data" => models}) when is_list(models) do
    models
    |> Enum.flat_map(fn
      %{"id" => id} when is_binary(id) -> [id]
      _other -> []
    end)
    |> MapSet.new()
  end

  defp model_ids(_body), do: MapSet.new()
end
