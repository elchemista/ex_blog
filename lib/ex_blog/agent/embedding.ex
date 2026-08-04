defmodule ExBlog.Agent.Embedding do
  @moduledoc """
  Environment-aware embedding boundary for Spectre routing.

  Development and test delegate to ExFastembed so the ExBlog dataset can train
  and exercise the optional 384-dimensional local classifier. Production
  delegates to `ExBlog.AI.Embedding`, which uses the configured OpenRouter model
  through the normal Req, redaction, budget, and accounting boundary.

  The split is strict: local classifier artifacts are never loaded in
  production, so their 384-dimensional vectors cannot mix with hosted
  1,024-dimensional semantic-cache rows. E5's `query:` prefix is applied only
  to the local adapter; hosted models receive the original redacted text.
  """

  @behaviour Spectre.Classifier.Embedding

  alias ExBlog.Agent.ClassifierConfig
  alias ExBlog.Config

  @local_adapter Spectre.Classifier.Embeddings.ExFastembed
  @hosted_adapter ExBlog.AI.Embedding

  @doc "Returns the embedding adapter selected by the current environment."
  @spec adapter() :: module()
  def adapter do
    Application.get_env(:ex_blog, :spectre_embedding_adapter, @hosted_adapter)
  end

  @doc "Returns whether this runtime is explicitly using the local encoder."
  @spec local?() :: boolean()
  def local?, do: adapter() == @local_adapter

  @doc "Returns a stable identity used to namespace persisted semantic rows."
  @spec identity(Config.t()) :: String.t()
  def identity(%Config{} = config) do
    case adapter() do
      @local_adapter ->
        "local:#{ClassifierConfig.encoder_model()}"

      @hosted_adapter ->
        "hosted:#{config.embedding_model}:#{config.embedding_dimensions}"

      custom ->
        "custom:#{inspect(custom)}"
    end
  end

  @impl Spectre.Classifier.Embedding
  @spec download(String.t(), keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def download(model, opts \\ []), do: call_adapter(:download, model, opts, fallback: :load)

  @impl Spectre.Classifier.Embedding
  @spec load(String.t(), keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def load(model, opts \\ []), do: call_adapter(:load, model, opts)

  @impl Spectre.Classifier.Embedding
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []) when is_binary(text) and is_list(opts) do
    text = if local?(), do: "query: " <> text, else: text
    call_adapter(:embed, text, opts)
  end

  defp call_adapter(function, value, opts, call_opts \\ []) do
    do_call_adapter(adapter(), function, value, opts, call_opts)
  end

  defp do_call_adapter(selected, function, value, opts, call_opts) do
    fallback = Keyword.get(call_opts, :fallback)

    cond do
      selected == __MODULE__ ->
        {:error, :recursive_spectre_embedding_adapter}

      not Code.ensure_loaded?(selected) ->
        {:error, {:missing_spectre_embedding_adapter, selected}}

      function_exported?(selected, function, 2) ->
        apply(selected, function, [value, opts])

      is_atom(fallback) and function_exported?(selected, fallback, 2) ->
        apply(selected, fallback, [value, opts])

      true ->
        {:error, {:missing_spectre_embedding_callback, selected, function}}
    end
  rescue
    exception ->
      {:error,
       {:spectre_embedding_exception, selected, exception.__struct__,
        Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:spectre_embedding_failure, selected, kind, reason}}
  end
end
