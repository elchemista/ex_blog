defmodule ExBlog.Telegram.Gateway do
  @moduledoc """
  Authenticated Telegram boundary. Unauthorized updates stop before Beam,
  Spectre, memory, logging, or provider calls.
  """

  alias ExBlog.Agent.Presenter
  alias ExBlog.Config
  alias Spectre.Result

  @telegram_limit 4_096

  @spec handle_update(term(), keyword()) :: :ignore | {:reply, [String.t()]} | {:error, term()}
  def handle_update(event, opts \\ []) do
    admin_id = Config.get().admin_telegram_id

    case {sender_id(event), from_me?(event)} do
      {^admin_id, false} -> authorized(event, opts)
      _unauthorized_or_outgoing -> :ignore
    end
  end

  @spec split(String.t(), pos_integer()) :: [String.t()]
  def split(text, limit \\ @telegram_limit) when is_binary(text) and limit > 0 do
    do_split(text, limit, [])
  end

  defp authorized(event, opts) do
    case Keyword.get(opts, :processor) do
      processor when is_function(processor, 1) -> processor.(event)
      _other -> process(event, opts)
    end
  end

  defp process(event, opts) do
    with {:ok, inbound} <-
           Spectre.Beam.decode(ExBlog.Agent, :telegram, event, authenticated?: true),
         input <- Spectre.Beam.to_input(inbound),
         {:ok, result} <-
           Spectre.ask(
             ExBlog.Agent,
             input,
             spectre_opts(opts, inbound.conversation_id)
           ),
         {:ok, text} <- resolve_result(result, opts, inbound.conversation_id) do
      chunks = split(text)
      {:reply, chunks}
    else
      :ignore -> :ignore
      {:error, _reason} = error -> error
    end
  end

  defp resolve_result(%Result{} = result, opts, conversation_id) do
    cond do
      Result.open_awaitable(result) != nil ->
        visible_text(result)

      executable_effect?(Result.pending_effect(result)) ->
        with {:ok, executed} <-
               Spectre.execute(
                 ExBlog.Agent,
                 result,
                 spectre_opts(opts, conversation_id)
               ) do
          action_text(executed)
        end

      Result.action_outcome(result) != nil ->
        action_text(result)

      Result.visible_reply?(result) ->
        visible_text(result)

      true ->
        {:ok, "Operazione completata."}
    end
  end

  defp executable_effect?(%{status: status}) when status in [:pending, :approved], do: true
  defp executable_effect?(_effect), do: false

  defp action_text(result) do
    case Result.action_outcome(result) do
      {:ok, value} -> {:ok, Presenter.present(value)}
      {:error, reason} -> {:ok, Presenter.present({:error, reason})}
      {:cancelled, _reason} -> {:ok, "Operazione annullata."}
      nil -> visible_text(result)
    end
  end

  defp visible_text(%Result{reply_text: text}) when is_binary(text) do
    if String.trim(text) == "", do: {:ok, "Operazione completata."}, else: {:ok, text}
  end

  defp spectre_opts(opts, conversation_id) do
    opts
    |> Keyword.take([:model, :req_options, :test_pid])
    |> Keyword.put(:conversation_id, to_string(conversation_id))
  end

  defp sender_id({:ex_gram_message, _jid, message}), do: sender_id(message)
  defp sender_id({:ex_gram_message, _session_id, _jid, message}), do: sender_id(message)

  defp sender_id(event) when is_map(event) do
    message = field(event, :message) || event
    sender = field(message, :from) || %{}
    field(sender, :id) || field(message, :sender_id)
  end

  defp sender_id(_event), do: nil

  defp from_me?({:ex_gram_message, _jid, message}), do: from_me?(message)
  defp from_me?({:ex_gram_message, _session_id, _jid, message}), do: from_me?(message)
  defp from_me?(event) when is_map(event), do: field(event, :from_me) == true
  defp from_me?(_event), do: false

  defp field(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp do_split("", _limit, []), do: [""]
  defp do_split("", _limit, chunks), do: Enum.reverse(chunks)

  defp do_split(text, limit, chunks) do
    if String.length(text) <= limit do
      Enum.reverse([text | chunks])
    else
      candidate = String.slice(text, 0, limit)
      chunk = break_at_newline(candidate)
      rest = String.slice(text, String.length(chunk)..-1//1) |> String.trim_leading("\n")
      do_split(rest, limit, [chunk | chunks])
    end
  end

  defp break_at_newline(candidate) do
    case candidate |> String.split("\n") |> Enum.drop(-1) do
      [] ->
        candidate

      lines ->
        case Enum.join(lines, "\n") do
          "" -> candidate
          chunk -> chunk
        end
    end
  end
end
