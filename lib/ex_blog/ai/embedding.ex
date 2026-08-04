defmodule ExBlog.AI.Embedding do
  @moduledoc """
  OpenRouter embedding boundary used by production Spectre routing and Prism.

  Calls pass through ExBlog's Req-backed Prism transport, so the same timeout,
  redaction, budget, and usage-accounting boundaries apply to embeddings and
  text generation.

  `ExBlog.Agent.Embedding` delegates here in production. Development and test
  may instead select ExFastembed to train and evaluate the optional local
  classifier. Keeping that choice in the environment-aware boundary prevents
  local 384-dimensional artifacts from mixing with hosted 1,024d vectors.
  """

  @behaviour Spectre.Classifier.Embedding

  alias ExBlog.Config
  alias Spectre.Prism.Adapters.OpenRouter

  @default_dimensions 1024

  @impl Spectre.Classifier.Embedding
  @spec load(String.t(), keyword()) :: {:ok, pos_integer()}
  def load(_model, opts \\ []), do: {:ok, configured_dimensions(opts)}

  @impl Spectre.Classifier.Embedding
  @spec download(String.t(), keyword()) :: {:ok, pos_integer()}
  def download(model, opts \\ []), do: load(model, opts)

  @impl Spectre.Classifier.Embedding
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []) when is_binary(text) and is_list(opts) do
    # Redaction happens again here because review tools can call the semantic
    # cache directly without passing through the normal Agent input pipeline.
    dimensions = configured_dimensions(opts)
    safe_text = Config.redact(text)
    request_opts = request_opts(opts, dimensions)

    with {:ok, vector} <- request_embedding(safe_text, request_opts, opts),
         :ok <- validate_vector(vector, dimensions) do
      {:ok, Enum.map(vector, &(&1 / 1))}
    end
  rescue
    exception ->
      {:error, {:embedding_exception, exception.__struct__, Exception.message(exception)}}
  catch
    :exit, reason -> {:error, {:embedding_exit, reason}}
    kind, reason -> {:error, {:embedding_failure, kind, reason}}
  end

  defp request_embedding(text, request_opts, opts) do
    case Keyword.get(opts, :embedding_fun) do
      fun when is_function(fun, 2) -> fun.(text, request_opts)
      _default -> OpenRouter.embed(text, request_opts)
    end
  end

  defp request_opts(opts, dimensions) do
    # Embeddings use the same budgeted Prism transport as completions. The
    # purpose/subject fields make vector costs visible in the budget ledger.
    [
      transport: ExBlog.AI.Transport,
      api_key: Config.fetch_secret!(:openrouter_api_key),
      app_name: "ExBlog",
      model: configured_model(opts),
      dimensions: dimensions,
      encoding_format: "float",
      purpose: :semantic_cache_embedding,
      ex_blog_level: :fast,
      subject_type: "semantic_route",
      conversation_id: Keyword.get(opts, :conversation_id),
      estimated_cost_eur: Keyword.get(opts, :embedding_estimated_cost_eur, "0.002"),
      receive_timeout: Application.get_env(:ex_blog, :openrouter_receive_timeout, 90_000)
    ]
    |> maybe_put(:req_options, Keyword.get(opts, :req_options))
  end

  defp configured_model(opts) do
    opts
    |> Keyword.get(:embedding_model, Config.get().embedding_model)
    |> String.replace_prefix("openrouter:", "")
  end

  defp configured_dimensions(opts) do
    case Keyword.get(opts, :embedding_dimensions, Config.get().embedding_dimensions) do
      dimensions when is_integer(dimensions) and dimensions > 0 -> dimensions
      _invalid -> @default_dimensions
    end
  end

  defp validate_vector(vector, dimensions) when is_list(vector) do
    cond do
      length(vector) != dimensions ->
        {:error, {:embedding_dimension_mismatch, dimensions, length(vector)}}

      Enum.all?(vector, &is_number/1) ->
        :ok

      true ->
        {:error, :invalid_embedding_vector}
    end
  end

  defp validate_vector(_vector, _dimensions), do: {:error, :invalid_embedding_vector}

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
