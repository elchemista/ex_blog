defmodule ExBlog.Telegram.Transport do
  @moduledoc """
  Owns the ExGram TDLib session used by ExBlog.

  Besides routing administrator messages, the process keeps an in-memory
  projection of the authorization state for the protected web interface. QR
  login links and two-factor hints are never persisted or logged.
  """

  use GenServer

  require Logger

  alias ExBlog.Config
  alias ExBlog.Telegram.Gateway

  @topic "telegram:admin_connection"
  @snapshot_event :telegram_connection_updated

  @type handler :: (term() -> :ignore | {:reply, [String.t()]} | {:error, term()})
  @type snapshot :: %{
          auth_state: atom(),
          connection_status: atom(),
          last_error?: boolean(),
          password_hint: String.t() | nil,
          qr_link: String.t() | nil,
          session_id: String.t()
        }
  @type state :: %{
          auth_state: atom(),
          client: module(),
          connection_status: atom(),
          handler: handler(),
          last_error?: boolean(),
          monitor_ref: reference(),
          password_hint: String.t() | nil,
          qr_link: String.t() | nil,
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

  @doc "Subscribes the caller to safe connection-state projections."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(ExBlog.PubSub, @topic)

  @doc "Returns the current Telegram authorization projection."
  @spec snapshot(GenServer.server()) :: snapshot()
  def snapshot(server \\ __MODULE__), do: GenServer.call(server, :snapshot)

  @doc "Reconnects the configured ExGram session."
  @spec connect(GenServer.server()) :: :ok | {:error, :telegram_unavailable}
  def connect(server \\ __MODULE__), do: GenServer.call(server, :connect)

  @doc "Requests a QR login link from ExGram."
  @spec request_qr(GenServer.server()) :: :ok | {:error, :telegram_unavailable}
  def request_qr(server \\ __MODULE__), do: GenServer.call(server, :request_qr)

  @doc "Submits the phone number requested by TDLib."
  @spec provide_phone_number(String.t(), GenServer.server()) ::
          :ok | {:error, :telegram_unavailable}
  def provide_phone_number(phone, server \\ __MODULE__) do
    GenServer.call(server, {:provide_phone_number, phone})
  end

  @doc "Submits the Telegram authentication code requested by TDLib."
  @spec provide_auth_code(String.t(), GenServer.server()) ::
          :ok | {:error, :telegram_unavailable}
  def provide_auth_code(code, server \\ __MODULE__) do
    GenServer.call(server, {:provide_auth_code, code})
  end

  @doc "Submits the Telegram two-factor password requested by TDLib."
  @spec provide_password(String.t(), GenServer.server()) ::
          :ok | {:error, :telegram_unavailable}
  def provide_password(password, server \\ __MODULE__) do
    GenServer.call(server, {:provide_password, password})
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
         auth_state: :starting,
         client: client,
         connection_status: :connecting,
         handler: handler,
         last_error?: false,
         monitor_ref: Process.monitor(session_pid),
         password_hint: nil,
         qr_link: nil,
         session_id: session_id,
         session_pid: session_pid
       }}
    else
      {:error, _reason} -> {:stop, :telegram_session_start_failed}
    end
  end

  @impl GenServer
  def handle_call(:snapshot, _from, state) do
    {:reply, public_snapshot(state), state}
  end

  def handle_call(:connect, _from, state) do
    run_client_action(state, :connecting, fn -> state.client.connect(state.session_id) end)
  end

  def handle_call(:request_qr, _from, state) do
    run_client_action(state, :requesting_qr, fn ->
      state.client.request_qr_code_login(state.session_id)
    end)
  end

  def handle_call({:provide_phone_number, phone}, _from, state) do
    run_client_action(state, :submitting_phone, fn ->
      state.client.provide_phone_number(state.session_id, phone)
    end)
  end

  def handle_call({:provide_auth_code, code}, _from, state) do
    run_client_action(state, :submitting_code, fn ->
      state.client.provide_auth_code(state.session_id, code)
    end)
  end

  def handle_call({:provide_password, password}, _from, state) do
    run_client_action(state, :submitting_password, fn ->
      state.client.provide_password(state.session_id, password)
    end)
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

  def handle_info({:ex_gram_session, :connected}, state) do
    state =
      state
      |> Map.put(:connection_status, client_status(state, :connecting))
      |> Map.put(:last_error?, false)
      |> broadcast_snapshot()

    {:noreply, state}
  end

  def handle_info({:ex_gram_session, :disconnected, _reason}, state) do
    {:noreply, state |> disconnected_state() |> broadcast_snapshot()}
  end

  def handle_info({:ex_gram_session, :terminated, _reason}, state) do
    {:noreply, state |> disconnected_state() |> broadcast_snapshot()}
  end

  def handle_info({:ex_gram_session, :error, _reason}, state) do
    Logger.warning("Telegram session reported an error")

    state =
      state
      |> Map.put(:last_error?, true)
      |> broadcast_snapshot()

    {:noreply, state}
  end

  def handle_info({:ex_gram_session, :auth, event}, state) do
    {:noreply, event |> apply_auth_event(state) |> broadcast_snapshot()}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp run_client_action(state, pending_state, operation) do
    case safe_client_call(operation) do
      :ok ->
        state =
          state
          |> Map.put(:auth_state, pending_state)
          |> Map.put(:last_error?, false)
          |> maybe_clear_qr(pending_state)
          |> broadcast_snapshot()

        {:reply, :ok, state}

      {:error, :telegram_unavailable} = error ->
        state = state |> Map.put(:last_error?, true) |> broadcast_snapshot()
        {:reply, error, state}
    end
  end

  defp safe_client_call(operation) do
    case operation.() do
      :ok -> :ok
      {:error, _reason} -> {:error, :telegram_unavailable}
      _other -> {:error, :telegram_unavailable}
    end
  rescue
    _exception -> {:error, :telegram_unavailable}
  catch
    :exit, _reason -> {:error, :telegram_unavailable}
  end

  defp apply_auth_event({:wait_phone_number}, state) do
    state
    |> Map.put(:auth_state, :wait_phone_number)
    |> Map.put(:connection_status, :authenticating)
    |> Map.put(:last_error?, false)
    |> Map.put(:password_hint, nil)
    |> Map.put(:qr_link, nil)
  end

  defp apply_auth_event({:wait_other_device_confirmation, link}, state)
       when is_binary(link) do
    state
    |> Map.put(:auth_state, :wait_other_device_confirmation)
    |> Map.put(:connection_status, :authenticating)
    |> Map.put(:last_error?, false)
    |> Map.put(:password_hint, nil)
    |> Map.put(:qr_link, link)
  end

  defp apply_auth_event({:wait_other_device_confirmation, nil}, state) do
    state
    |> Map.put(:auth_state, :requesting_qr)
    |> Map.put(:connection_status, :authenticating)
    |> Map.put(:qr_link, nil)
  end

  defp apply_auth_event({:wait_code, _code_info}, state) do
    state
    |> Map.put(:auth_state, :wait_code)
    |> Map.put(:connection_status, :authenticating)
    |> Map.put(:last_error?, false)
    |> Map.put(:qr_link, nil)
  end

  defp apply_auth_event({:wait_password, hint}, state) do
    state
    |> Map.put(:auth_state, :wait_password)
    |> Map.put(:connection_status, :authenticating)
    |> Map.put(:last_error?, false)
    |> Map.put(:password_hint, safe_hint(hint))
    |> Map.put(:qr_link, nil)
  end

  defp apply_auth_event({:status, :ready}, state) do
    state
    |> Map.put(:auth_state, :ready)
    |> Map.put(:connection_status, :connected)
    |> Map.put(:last_error?, false)
    |> Map.put(:password_hint, nil)
    |> Map.put(:qr_link, nil)
  end

  defp apply_auth_event({:status, :closed}, state), do: disconnected_state(state)

  defp apply_auth_event({:error, _reason}, state), do: Map.put(state, :last_error?, true)
  defp apply_auth_event(_event, state), do: state

  defp disconnected_state(state) do
    state
    |> Map.put(:auth_state, :disconnected)
    |> Map.put(:connection_status, :disconnected)
    |> Map.put(:password_hint, nil)
    |> Map.put(:qr_link, nil)
  end

  defp safe_hint(hint) when is_binary(hint), do: String.slice(hint, 0, 120)
  defp safe_hint(_hint), do: nil

  defp maybe_clear_qr(state, :requesting_qr), do: Map.put(state, :qr_link, nil)
  defp maybe_clear_qr(state, _pending_state), do: state

  defp client_status(state, fallback) do
    case state.client.status(state.session_id) do
      status when status in [:idle, :connecting, :authenticating, :connected, :disconnected] ->
        status

      _other ->
        fallback
    end
  rescue
    _exception -> fallback
  catch
    :exit, _reason -> fallback
  end

  defp broadcast_snapshot(state) do
    _result =
      Phoenix.PubSub.broadcast(
        ExBlog.PubSub,
        @topic,
        {@snapshot_event, public_snapshot(state)}
      )

    state
  end

  defp public_snapshot(state) do
    Map.take(state, [
      :auth_state,
      :connection_status,
      :last_error?,
      :password_hint,
      :qr_link,
      :session_id
    ])
  end

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
