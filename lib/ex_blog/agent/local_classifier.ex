defmodule ExBlog.Agent.LocalClassifier do
  @moduledoc """
  Application-owned adapter for Spectre's trained intent classifier.

  The router calls this provider after deterministic and exact-cache evidence.
  A confident local result avoids the remote LLM classifier entirely; an
  unavailable or uncertain model simply leaves arbitration to semantic search
  and the configured OpenRouter fallback.

  The explicit enable switch is useful for incident recovery. Disabling the
  local model never disables exact dataset matches or the LLM fallback.
  """

  alias ExBlog.Agent.ClassifierConfig

  @doc "Classifies one administrator request with the warm local artifact."
  @spec classify(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def classify(text, opts) when is_binary(text) and is_list(opts) do
    if ClassifierConfig.local_enabled?() do
      Spectre.Classifier.classify(text, opts)
    else
      {:error, :local_classifier_disabled}
    end
  end
end
