defmodule ExBlog.AI do
  @moduledoc """
  Spectre Stack and direct AI boundary for ExBlog.
  """

  use Spectre.Stack, id: :ex_blog

  alias ExBlog.AI.OpenRouter
  alias ExBlog.Config

  require OpenRouter

  install Spectre.Prism, max_attempts: 2 do
    provider(:openrouter, OpenRouter,
      models: [
        fast: "ex-blog/runtime-fast",
        balanced: "ex-blog/runtime-balanced",
        deep: "ex-blog/runtime-deep"
      ],
      classifier: :fast,
      embedding: false
    )

    purpose(:route_classification, prefer: :fast)
    purpose(:response_generation, prefer: :balanced)
    purpose(:article_generation, prefer: :deep)
    purpose(:page_audit, prefer: :balanced)
    default(:balanced)
  end

  install Spectre.Beam, delivery: :caller_owned do
    channel(:telegram,
      type: :telegram,
      adapter: Spectre.Beam.Adapters.ExGram,
      capabilities: [:text],
      planner_exposure: :none,
      typing: true
    )
  end

  @spec complete(:fast | :balanced | :deep, String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def complete(level, prompt, opts \\ []) when level in [:fast, :balanced, :deep] do
    opts = Keyword.put(opts, :model, OpenRouter.marker(level))
    OpenRouter.complete(prompt, opts)
  end

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
