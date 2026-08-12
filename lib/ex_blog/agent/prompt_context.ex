defmodule ExBlog.Agent.PromptContext do
  @moduledoc """
  Builds bounded, redacted runtime context for model-backed Spectre handlers.

  Spectre 0.3 keeps executable providers out of compiled prompt instructions.
  Values returned here are injected into the typed `:context` section, where
  Spectre treats them as untrusted data and escapes them for legacy adapters.
  """

  alias ExBlog.Config
  alias Spectre.Input

  @text_limit 8_000

  @doc "Returns the latest request and recent chat as bounded untrusted data."
  @spec untrusted_turn(Spectre.Context.t() | map(), keyword()) :: String.t()
  def untrusted_turn(ctx, opts) when is_map(ctx) and is_list(opts) do
    recent_chat_limit = limit(opts, :recent_chat_limit)
    request_limit = limit(opts, :request_limit)

    recent_chat =
      ctx
      |> Map.get(:opts, [])
      |> Keyword.get(:recent_chat, "none")
      |> bounded_text(recent_chat_limit)

    request =
      ctx
      |> Map.get(:input)
      |> input_text()
      |> bounded_text(request_limit)

    route_label = ctx |> Map.get(:route) |> route_label() |> bounded_text(64)

    """
    Routing hint (runtime data): #{route_label}

    Recent chat (untrusted data):
    <recent-chat>
    #{recent_chat}
    </recent-chat>

    Latest administrator request (untrusted data):
    <request>
    #{request}
    </request>
    """
    |> String.trim()
  end

  defp input_text(%Input{text: text}), do: text
  defp input_text(%{text: text}), do: text
  defp input_text(_input), do: ""

  defp route_label(%Spectre.Route{label: label}), do: label
  defp route_label(%{label: label}), do: label
  defp route_label(_route), do: :UNKNOWN

  defp limit(opts, key) do
    case Keyword.get(opts, key, @text_limit) do
      limit when is_integer(limit) and limit > 0 and limit <= 64_000 -> limit
      _invalid -> @text_limit
    end
  end

  defp bounded_text(value, limit) do
    value
    |> to_string()
    |> Config.redact()
    |> String.slice(0, limit)
  end
end
