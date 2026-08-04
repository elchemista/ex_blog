defmodule ExBlog.Telegram.Gateway do
  @moduledoc """
  Authenticated Telegram boundary. Unauthorized updates stop before Beam,
  Spectre, memory, logging, or provider calls.
  """

  require Logger

  alias ExBlog.Agent.Instance
  alias ExBlog.Agent.Presenter
  alias ExBlog.Config
  alias ExBlog.Telegram.Image
  alias Spectre.Result

  @telegram_limit 4_096

  @spec handle_update(term(), keyword()) :: :ignore | {:reply, [String.t()]} | {:error, term()}
  def handle_update(event, opts \\ []) do
    admin_username = Config.get().admin_telegram_username
    username = sender_username(event, opts)

    case username do
      ^admin_username ->
        Logger.info(
          "Telegram administrator message accepted " <>
            "sender_id=#{inspect(sender_id(event))} direction=#{message_direction(event)}"
        )

        authorized(event, opts)

      _unauthorized ->
        Logger.info(
          "Telegram message ignored: sender is not the configured administrator " <>
            "sender_id=#{inspect(sender_id(event))} " <>
            "username_resolved=#{is_binary(username)} direction=#{message_direction(event)}"
        )

        :ignore
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
           Spectre.Beam.decode(ExBlog.Agent, :telegram, event,
             adapter_opts: [authenticated?: true]
           ),
         {:ok, input} <- Image.prepare(inbound),
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
      :ignore ->
        :ignore

      {:error, :telegram_image_too_large} ->
        {:reply, ["The image is too large. The limit is 10 MB."]}

      {:error, reason}
      when reason in [
             :missing_telegram_file_id,
             :invalid_telegram_image_size,
             :unauthenticated_telegram_image
           ] ->
        {:reply, ["I cannot use this Telegram image. Send a valid photo."]}

      {:error, _reason} = error ->
        error
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
        {:ok, "Operation completed."}
    end
  end

  defp executable_effect?(%{status: status}) when status in [:pending, :approved], do: true
  defp executable_effect?(_effect), do: false

  defp action_text(result) do
    case Result.action_outcome(result) do
      {:ok, value} -> {:ok, Presenter.present(value)}
      {:error, reason} -> {:ok, Presenter.present({:error, reason})}
      {:cancelled, _reason} -> {:ok, "Operation cancelled."}
      nil -> visible_text(result)
    end
  end

  defp visible_text(%Result{reply_text: text}) when is_binary(text) do
    if String.trim(text) == "", do: {:ok, "Operation completed."}, else: {:ok, text}
  end

  defp spectre_opts(opts, conversation_id) do
    opts
    |> Keyword.take([
      :model,
      :req_options,
      :test_pid,
      :ai_complete,
      :telegram_media_downloader,
      :telegram_session_id,
      :article_asset_root
    ])
    |> Keyword.put(:conversation_id, to_string(conversation_id))
    |> Instance.put_instance()
  end

  defp sender_id({:ex_gram_message, _jid, message}), do: sender_id(message)
  defp sender_id({:ex_gram_message, _session_id, _jid, message}), do: sender_id(message)

  defp sender_id(event) when is_map(event) do
    message = field(event, :message) || event
    sender = field(message, :from) || %{}
    field(sender, :id) || field(message, :sender_id)
  end

  defp sender_id(_event), do: nil

  defp sender_username(event, opts) do
    username = direct_sender_username(event) || resolved_sender_username(event, opts)
    normalize_username(username)
  end

  defp direct_sender_username({:ex_gram_message, _jid, message}),
    do: direct_sender_username(message)

  defp direct_sender_username({:ex_gram_message, _session_id, _jid, message}),
    do: direct_sender_username(message)

  defp direct_sender_username(event) when is_map(event) do
    message = field(event, :message) || event
    sender = field(message, :from) || %{}

    field(sender, :username) || field(message, :sender_username) || field(message, :username)
  end

  defp direct_sender_username(_event), do: nil

  defp resolved_sender_username(event, opts) do
    with sender_id when is_integer(sender_id) <- sender_id(event),
         result <- resolve_username(sender_id, opts) do
      username_from_result(result)
    else
      _missing_sender -> nil
    end
  end

  defp resolve_username(sender_id, opts) do
    resolver = Keyword.get(opts, :username_resolver, &default_username_resolver/1)

    try do
      resolver.(sender_id)
    rescue
      _error -> nil
    catch
      _kind, _reason -> nil
    end
  end

  defp default_username_resolver(sender_id) do
    session_id = Config.get().telegram_session_id
    contact = ExGram.get_contact(session_id, sender_id)

    case username_from_result(contact) do
      username when is_binary(username) ->
        username

      _missing_username ->
        ExGram.send_request_sync(
          session_id,
          %{"@type" => "getUser", "user_id" => sender_id},
          timeout_ms: 5_000
        )
    end
  end

  defp username_from_result({:ok, value}), do: username_from_result(value)
  defp username_from_result(value) when is_binary(value), do: value

  defp username_from_result(value) when is_map(value) do
    legacy_username = field(value, :username)
    usernames = field(value, :usernames)

    present_username(legacy_username) || username_from_usernames(usernames)
  end

  defp username_from_result(_value), do: nil

  defp username_from_usernames(usernames) when is_map(usernames) do
    active_username =
      usernames
      |> field(:active_usernames)
      |> first_present_username()

    active_username || present_username(field(usernames, :editable_username))
  end

  defp username_from_usernames(_usernames), do: nil

  defp first_present_username(usernames) when is_list(usernames) do
    Enum.find_value(usernames, &present_username/1)
  end

  defp first_present_username(_usernames), do: nil

  defp present_username(username) when is_binary(username) do
    if String.trim(username) == "", do: nil, else: username
  end

  defp present_username(_username), do: nil

  defp normalize_username(username) when is_binary(username) do
    username
    |> String.trim()
    |> String.trim_leading("@")
    |> String.downcase()
  end

  defp normalize_username(_username), do: nil

  defp message_direction({:ex_gram_message, _jid, message}), do: message_direction(message)

  defp message_direction({:ex_gram_message, _session_id, _jid, message}),
    do: message_direction(message)

  defp message_direction(event) when is_map(event) do
    if field(event, :from_me) == true, do: :outgoing, else: :incoming
  end

  defp message_direction(_event), do: :unknown

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
