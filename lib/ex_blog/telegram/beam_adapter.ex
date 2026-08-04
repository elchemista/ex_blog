defmodule ExBlog.Telegram.BeamAdapter do
  @moduledoc """
  Spectre Beam's ExGram channel with native TDLib typing actions.

  ExGram exposes raw TDLib requests but no `send_typing/3` helper, so the
  production path sends `sendChatAction` directly. Compatible test/provider
  overrides continue through the bundled adapter.
  """

  @behaviour Spectre.Beam.Channel

  alias Spectre.Beam.Adapters.ExGram, as: Adapter

  @impl Spectre.Beam.Channel
  defdelegate capabilities(opts), to: Adapter

  @impl Spectre.Beam.Channel
  defdelegate decode(event, opts), to: Adapter

  @impl Spectre.Beam.Channel
  defdelegate deliver(outbound, opts), to: Adapter

  @impl Spectre.Beam.Channel
  defdelegate subscribe(opts), to: Adapter

  @impl Spectre.Beam.Channel
  defdelegate unsubscribe(opts), to: Adapter

  @impl Spectre.Beam.Channel
  def typing(chat_id, composing?, opts) do
    case Keyword.get(opts, :module) do
      module when module in [nil, ExGram] ->
        opts |> client() |> send_chat_action(chat_id, composing?)

      _override ->
        Adapter.typing(chat_id, composing?, opts)
    end
  end

  defp send_chat_action({:ok, client}, chat_id, composing?) do
    session_id = if is_pid(client), do: ExGram.get_session_id(client), else: client
    action = if composing?, do: "chatActionTyping", else: "chatActionCancel"

    ExGram.send_request(session_id, %{
      "@type" => "sendChatAction",
      "chat_id" => chat_id,
      "action" => %{"@type" => action}
    })
  end

  defp send_chat_action({:error, _reason} = error, _chat_id, _composing?), do: error

  defp client(opts) do
    case Keyword.get(opts, :client, Keyword.get(opts, :session)) do
      nil -> {:error, :missing_beam_adapter_client}
      client -> {:ok, client}
    end
  end
end
