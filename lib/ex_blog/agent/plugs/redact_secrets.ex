defmodule ExBlog.Agent.Plugs.RedactSecrets do
  @moduledoc false

  @behaviour Spectre.Input.Plug

  @impl Spectre.Input.Plug
  def init(opts), do: opts

  @impl Spectre.Input.Plug
  def call(%Spectre.Input{} = input, _context, _opts) do
    {:cont, %{input | text: ExBlog.Config.redact(input.text), raw: nil}}
  end
end
