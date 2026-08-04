defmodule ExBlog.AI.OpenRouter do
  @moduledoc """
  Runtime bridge around Prism's OpenRouter adapter.

  The Stack contains stable semantic placeholders only. This bridge resolves
  the deployed model names and credential at the instant of each call.
  """

  @behaviour Spectre.Prism.Adapter
  @behaviour Spectre.LLM
  @behaviour Spectre.Classifier.Embedding

  alias ExBlog.AI.Embedding
  alias ExBlog.Config
  alias Spectre.Prism.Adapters.OpenRouter

  @markers %{
    fast: "ex-blog/runtime-fast",
    balanced: "ex-blog/runtime-balanced",
    deep: "ex-blog/runtime-deep"
  }
  @embedding_marker "ex-blog/runtime-embedding"

  @impl Spectre.Prism.Adapter
  def catalog do
    OpenRouter.catalog()
    |> Map.update!(:options, fn options ->
      options
      |> Keyword.put(:transport, ExBlog.AI.Transport)
      |> Keyword.put(:app_name, "ExBlog")
    end)
    |> Map.put(:embedding, model: @embedding_marker, dimensions: 1024)
  end

  @impl Spectre.LLM
  def complete(prompt, opts \\ []) when is_binary(prompt) and is_list(opts) do
    OpenRouter.complete(Config.redact(prompt), runtime_opts(opts))
  end

  @impl Spectre.LLM
  def complete_plan(%Spectre.Prompt.Plan{} = plan, opts) when is_list(opts) do
    OpenRouter.complete_plan(redact_plan(plan), runtime_opts(opts))
  end

  @impl Spectre.Classifier.Embedding
  def load(_model, opts \\ []), do: Embedding.load(@embedding_marker, opts)

  @impl Spectre.Classifier.Embedding
  def download(_model, opts \\ []), do: Embedding.download(@embedding_marker, opts)

  @impl Spectre.Classifier.Embedding
  def embed(text, opts \\ []), do: Embedding.embed(text, opts)

  @spec marker(:fast | :balanced | :deep) :: String.t()
  def marker(level), do: Map.fetch!(@markers, level)

  defp runtime_opts(opts) do
    config = Config.get()
    selected = Keyword.get(opts, :model)
    level = selected_level(selected, opts)

    model =
      if classifier_purpose?(opts),
        do: config.classifier_model,
        else: runtime_model(level, config)

    opts
    |> Keyword.put(:transport, ExBlog.AI.Transport)
    |> Keyword.put(:api_key, Config.fetch_secret!(:openrouter_api_key))
    |> Keyword.put(:app_name, "ExBlog")
    |> Keyword.put(:model, model)
    |> Keyword.put(:ex_blog_level, level)
    |> Keyword.put_new(:receive_timeout, 90_000)
  end

  defp selected_level(selected, opts) do
    if classifier_purpose?(opts) do
      :fast
    else
      marker_level(selected)
    end
  end

  defp marker_level(selected) do
    Enum.find_value(@markers, :balanced, fn
      {level, ^selected} -> level
      _marker -> nil
    end)
  end

  defp runtime_model(:fast, config), do: config.fast_model
  defp runtime_model(:balanced, config), do: config.balanced_model
  defp runtime_model(:deep, config), do: config.deep_model

  defp classifier_purpose?(opts),
    do: Keyword.get(opts, :purpose) in [:classifier, :route_classification]

  defp redact_plan(plan) do
    plan =
      Enum.reduce([:protected, :instructions, :context, :examples, :task], plan, fn field, acc ->
        Map.update!(acc, field, &Enum.map(&1, fn fragment -> redact_fragment(fragment) end))
      end)

    %{plan | rendered: Config.redact(plan.rendered)}
  end

  defp redact_fragment(%{content: content} = fragment) when is_binary(content),
    do: %{fragment | content: Config.redact(content)}

  defp redact_fragment(fragment), do: fragment
end
