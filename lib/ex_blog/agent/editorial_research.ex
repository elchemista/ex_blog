defmodule ExBlog.Agent.EditorialResearch do
  @moduledoc """
  Request-scoped source research for the guided editorial workflow.

  Each public URL is rendered with Spectre Lens and converted through
  `SpectreLens.agent_context/2` before it reaches the summarization model. Raw
  page projections never enter Spectre state: callers receive only sanitized
  source identities, a bounded source-grounded summary, and diagnostics.

  One Lens runtime is reused sequentially for the bounded URL set. Every tab
  and the runtime itself are closed even when navigation, perception, or model
  summarization fails.
  """

  alias ExBlog.AI
  alias ExBlog.Config
  alias ExBlogWeb.Prompt
  alias SpectreLens.View

  @include [:markdown, :semantic_tree, :semantic_text, :links, :structured_data]
  @max_sources 3
  @max_url_bytes 2_048
  @max_context_characters 18_000
  @max_summary_characters 6_000

  @type source :: %{required(:url) => String.t(), required(:title) => String.t() | nil}
  @type result :: %{
          required(:sources) => [source()],
          required(:summary) => String.t(),
          required(:warnings) => [String.t()]
        }

  @doc "Researches one to three public URLs and returns a bounded editorial digest."
  @spec collect([String.t()], keyword()) :: {:ok, result()} | {:error, term()}
  def collect(urls, opts \\ [])

  def collect(urls, opts) when is_list(urls) and is_list(opts) do
    lens = Keyword.get(opts, :lens, SpectreLens)

    with {:ok, urls} <- normalize_urls(urls),
         {:ok, runtime} <- lens.open(lens_options(opts)) do
      try do
        research_runtime(lens, runtime, urls, opts)
      after
        _result = lens.close(runtime)
      end
    end
  end

  def collect(_urls, _opts), do: {:error, :invalid_source_urls}

  defp research_runtime(lens, runtime, urls, opts) do
    {researched, failures} =
      Enum.reduce(urls, {[], []}, fn url, {sources, errors} ->
        case inspect_source(lens, runtime, url) do
          {:ok, source} -> {sources ++ [source], errors}
          {:error, reason} -> {sources, errors ++ [{url, reason}]}
        end
      end)

    case researched do
      [] ->
        {:error, {:source_research_failed, Enum.map(failures, &failure_warning/1)}}

      sources ->
        with {:ok, summary} <- summarize(sources, opts) do
          {:ok,
           %{
             sources: Enum.map(sources, &Map.take(&1, [:url, :title])),
             summary: summary,
             warnings: Enum.map(failures, &failure_warning/1)
           }}
        end
    end
  end

  defp inspect_source(lens, runtime, requested_url) do
    with {:ok, tab} <- lens.new_tab(runtime, url: requested_url) do
      try do
        with {:ok, %View{} = view} <- lens.look(tab, include: @include),
             {:ok, context} <- source_context(lens, view, requested_url) do
          {:ok,
           %{
             url: resolved_url(view.url, requested_url),
             title: normalize_title(view.title),
             context: context,
             diagnostics: normalize_diagnostics(view.warnings ++ view.errors)
           }}
        end
      after
        _result = lens.close_tab(tab)
      end
    end
  end

  defp source_context(lens, view, requested_url) do
    {view, preference} =
      cond do
        present?(view.markdown) ->
          {%{view | markdown: limit(view.markdown)}, :markdown}

        present?(view.semantic_text) ->
          {%{view | semantic_text: limit(view.semantic_text)}, :semantic_text}

        true ->
          {%{view | markdown: "[No readable textual content was detected.]"}, :markdown}
      end

    safe_view = %{view | url: resolved_url(view.url, requested_url)}
    lens.agent_context(safe_view, prefer: preference)
  end

  defp summarize(sources, opts) do
    prompt =
      Prompt.editorial_research(%{
        topic: Keyword.get(opts, :topic, "New article"),
        source_context: source_prompt_context(sources)
      })

    completion_opts = [
      purpose: :source_research,
      subject_type: "editorial_research",
      subject_ref: research_ref(sources),
      conversation_id: Keyword.get(opts, :conversation_id),
      estimated_cost_eur: Keyword.get(opts, :estimated_cost_eur, "0.03")
    ]

    result =
      case Keyword.get(opts, :summarizer) do
        fun when is_function(fun, 1) -> fun.(prompt)
        nil -> complete(prompt, completion_opts, opts)
        _invalid -> {:error, :invalid_source_summarizer}
      end

    normalize_summary(result)
  end

  defp complete(prompt, completion_opts, opts) do
    completion_opts =
      case Keyword.get(opts, :req_options) do
        values when is_list(values) -> Keyword.put(completion_opts, :req_options, values)
        _missing -> completion_opts
      end

    case Keyword.get(opts, :ai_complete) do
      fun when is_function(fun, 3) -> fun.(:balanced, prompt, completion_opts)
      _default -> AI.complete(:balanced, prompt, completion_opts)
    end
  end

  defp normalize_summary({:ok, %{text: text}}), do: summary_text(text)
  defp normalize_summary({:ok, %{"text" => text}}), do: summary_text(text)
  defp normalize_summary({:ok, text}), do: summary_text(text)
  defp normalize_summary({:error, _reason} = error), do: error
  defp normalize_summary(other), do: summary_text(other)

  defp summary_text(text) when is_binary(text) do
    summary =
      text
      |> Config.redact()
      |> String.trim()
      |> String.replace(~r/^```(?:markdown|text)?\s*/iu, "")
      |> String.replace(~r/\s*```$/u, "")
      |> String.trim()
      |> String.slice(0, @max_summary_characters)

    if summary == "", do: {:error, :empty_source_summary}, else: {:ok, summary}
  end

  defp summary_text(_text), do: {:error, :invalid_source_summary}

  defp source_prompt_context(sources) do
    sources
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {source, index} ->
      diagnostics =
        case source.diagnostics do
          [] -> "none"
          values -> Enum.map_join(values, "; ", & &1)
        end

      """
      Source #{index}
      URL: #{source.url}
      Title: #{source.title || "not available"}
      Lens diagnostics: #{diagnostics}
      #{source.context}
      """
    end)
  end

  defp normalize_urls(urls) do
    urls = urls |> Enum.uniq() |> Enum.take(@max_sources + 1)

    case length(urls) do
      0 -> {:error, :source_url_required}
      count when count > @max_sources -> {:error, {:too_many_source_urls, @max_sources}}
      _count -> Enum.reduce_while(urls, {:ok, []}, &append_normalized_url/2)
    end
  end

  defp append_normalized_url(url, {:ok, normalized}) do
    case normalize_url(url) do
      {:ok, value} -> {:cont, {:ok, normalized ++ [value]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp normalize_url(url) when is_binary(url) do
    url = url |> Config.redact() |> String.trim()

    if byte_size(url) > @max_url_bytes or Regex.match?(~r/\s/u, url) do
      {:error, :invalid_source_url}
    else
      case URI.parse(url) do
        %URI{scheme: scheme, host: host, userinfo: nil}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          {:ok, url}

        _other ->
          {:error, :invalid_source_url}
      end
    end
  rescue
    _exception -> {:error, :invalid_source_url}
  end

  defp normalize_url(_url), do: {:error, :invalid_source_url}

  defp lens_options(opts) do
    opts
    |> Keyword.get(:lens_opts, [])
    |> Keyword.put(:instances, 1)
    |> Keyword.put(:network_policy, :public)
  end

  defp resolved_url(observed, requested) do
    candidate = if valid_url?(observed), do: observed, else: requested
    display_url(candidate)
  end

  defp valid_url?(value) when is_binary(value), do: match?({:ok, _url}, normalize_url(value))
  defp valid_url?(_value), do: false

  defp display_url(url), do: SpectreLens.URLPolicy.sanitize(Config.redact(url))

  defp normalize_title(title) when is_binary(title) do
    case title |> Config.redact() |> String.trim() do
      "" -> nil
      value -> String.slice(value, 0, 300)
    end
  end

  defp normalize_title(_title), do: nil

  defp normalize_diagnostics(values) do
    Enum.map(values, fn value ->
      value
      |> inspect(limit: 20, printable_limit: 500)
      |> Config.redact()
      |> String.slice(0, 500)
    end)
  end

  defp failure_warning({url, reason}) do
    "Could not inspect #{display_url(url)}: " <>
      (reason |> inspect(limit: 20, printable_limit: 500) |> Config.redact())
  end

  defp research_ref([source | _sources]), do: source.url
  defp research_ref([]), do: "editorial-sources"

  defp limit(value) when is_binary(value), do: String.slice(value, 0, @max_context_characters)
  defp limit(_value), do: ""

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
