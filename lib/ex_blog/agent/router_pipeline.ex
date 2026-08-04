defmodule ExBlog.Agent.RouterPipeline do
  @moduledoc """
  Spectre routing pipeline with deterministic intake and semantic reuse.

  Regex and the active nested-flow cursor run first. Only a request that has no
  deterministic winner reaches exact or vector semantic lookup, and only a
  cache miss can fall through to the LLM classifier.
  """

  alias ExBlog.Agent.Router.Plugs.CreationContinuation
  alias Spectre.Router.Context

  @spec call(Context.t()) :: {:ok, Context.t()} | {:error, term()}
  def call(%Context{} = context) do
    Spectre.Pipeline.run(context, [
      Spectre.Router.Plugs.Regex,
      CreationContinuation,
      Spectre.Router.Plugs.SemanticCacheExact,
      Spectre.Router.Plugs.SemanticCacheSearch,
      Spectre.Router.Plugs.Arbitrate,
      Spectre.Router.Plugs.Terminalize
    ])
  end
end
