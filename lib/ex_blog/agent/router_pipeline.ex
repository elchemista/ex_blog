defmodule ExBlog.Agent.RouterPipeline do
  @moduledoc """
  Spectre routing pipeline with deterministic article-intake continuation.
  """

  alias ExBlog.Agent.Router.Plugs.CreationContinuation
  alias Spectre.Router.Context

  @spec call(Context.t()) :: {:ok, Context.t()} | {:error, term()}
  def call(%Context{} = context) do
    Spectre.Pipeline.run(context, [
      Spectre.Router.Plugs.Regex,
      CreationContinuation,
      Spectre.Router.Plugs.Arbitrate,
      Spectre.Router.Plugs.Terminalize
    ])
  end
end
