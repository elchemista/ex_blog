defmodule ExBlog.Telegram.Transport do
  @moduledoc """
  Owns the ExGram TDLib session used by ExBlog.

  The process subscribes to normalized messages from the configured session,
  lets `ExBlog.Telegram.Gateway` enforce the administrator boundary, and sends
  replies to the originating chat. Telegram credentials are fetched during
  `init/1` and are not retained in the GenServer state.
  """

  use GenServer

  require Logger

  alias ExBlog.Config
  alias ExBlog.Telegram.Gateway

  @type handler :: (term() -> :ignore | {:reply, [String.t()]} | {:error, term()})
  @type state :: %{
          client: module(),
          handler: handler(),
          monitor_ref: reference(),
          session_id: String.t(),
          session_pid: pid()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @impl GenServer
  def init(opts) do
    config = Config.get()
    client = Keyword.get(opts, :client, ExGram)
    handler = Keyword.get(opts, :handler, &Gateway.handle_update/1)
    session_id = Keyword.get(opts, :session_id, config.telegram_session_id)

    database_directory =
      Keyword.get_lazy(opts, :database_directory, fn ->
        Path.join([config.data_dir, "telegram", session_id])
      end)

    session_opts = [
      session_id: session_id,
      api_id: Keyword.get(opts, :api_id, config.telegram_api_id),
      api_hash:
        Keyword.get_lazy(opts, :api_hash, fn -> Config.fetch_secret!(:telegram_api_hash) end),
      database_directory: database_directory
    ]

    with :ok <- File.mkdir_p(database_directory),
         {:ok, session_pid} <- ensure_session(client, session_opts),
         :ok <- client.subscribe(session_id),
         :ok <- client.connect(session_id) do
      {:ok,
       %{
         client: client,
         handler: handler,
         monitor_ref: Process.monitor(session_pid),
         session_id: session_id,
         session_pid: session_pid
       }}
    else
      {:error, _reason} -> {:stop, :telegram_session_start_failed}
    end
  end

  @impl GenServer
  def handle_info({:ex_gram_message, jid, message} = event, state) when is_map(message) do
    case state.handler.(event) do
      :ignore ->
        {:noreply, state}

      {:reply, chunks} when is_list(chunks) ->
        deliver(chunks, jid, state)
        {:noreply, state}

      {:error, _reason} ->
        Logger.warning("Telegram message processing failed")
        {:noreply, state}
    end
  end

  def handle_info(
        {:DOWN, ref, :process, pid, _reason},
        %{monitor_ref: ref, session_pid: pid} = state
      ) do
    {:stop, :telegram_session_stopped, state}
  end

  def handle_info({:ex_gram_session, :error, _reason}, state) do
    Logger.warning("Telegram session reported an error")
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp ensure_session(client, session_opts) do
    case client.start_link(session_opts) do
      {:ok, pid} when is_pid(pid) -> {:ok, pid}
      {:error, {:already_started, pid}} when is_pid(pid) -> {:ok, pid}
      {:error, _reason} = error -> error
    end
  end

  defp deliver(chunks, jid, state) do
    result =
      Enum.reduce_while(chunks, :ok, fn chunk, :ok ->
        case state.client.send_message(state.session_id, jid, chunk) do
          :ok -> {:cont, :ok}
          {:ok, _message_id} -> {:cont, :ok}
          {:error, _reason} -> {:halt, :error}
        end
      end)

    if result == :error do
      Logger.warning("Telegram reply delivery failed")
    end

    :ok
  end
end
