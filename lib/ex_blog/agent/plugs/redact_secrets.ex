defmodule ExBlog.Agent.Plugs.RedactSecrets do
  @moduledoc """
  Last input-sanitization step before routing and persistence.

  `ExBlog.Config.redact/1` replaces configured credential values in normalized
  text. The plug also clears `Spectre.Input.raw`; otherwise the original secret
  could bypass the sanitized `text` field and later reach state, memory,
  journaling, a model prompt, or an error report.
  """

  @behaviour Spectre.Input.Plug

  @impl Spectre.Input.Plug
  def init(opts), do: opts

  @impl Spectre.Input.Plug
  def call(%Spectre.Input{} = input, _context, _opts) do
    {:cont, %{input | text: ExBlog.Config.redact(input.text), raw: nil}}
  end
end
