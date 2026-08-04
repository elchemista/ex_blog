defmodule ExBlog.Agent.Embedding do
  @moduledoc """
  Local embedding boundary shared by trained routing and semantic cache search.

  The classifier trainer stores vectors produced by ExFastembed in
  `semantic_cache.jsonl`. Runtime queries must use the same adapter and model;
  otherwise Vettore would compare vectors with incompatible dimensions. This
  small application-owned boundary makes that invariant explicit and keeps
  OpenRouter embeddings out of the routing hot path.

  E5 models are trained with textual role prefixes. ExBlog uses `query:` for
  both corpus rows and runtime requests because intent classification and
  semantic reuse are symmetric similarity tasks. Applying the prefix in this
  shared boundary guarantees that training, warmup, and live inference cannot
  silently diverge.
  """

  @behaviour Spectre.Classifier.Embedding

  alias Spectre.Classifier.Embeddings.ExFastembed

  @impl Spectre.Classifier.Embedding
  @spec download(String.t(), keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def download(model, opts \\ []), do: ExFastembed.download(model, opts)

  @impl Spectre.Classifier.Embedding
  @spec load(String.t(), keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def load(model, opts \\ []), do: ExFastembed.load(model, opts)

  @impl Spectre.Classifier.Embedding
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(text, opts \\ []), do: ExFastembed.embed("query: " <> text, opts)
end
