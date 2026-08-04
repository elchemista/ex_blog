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
  alias Spectre.Beam.{Content, Receipt}

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
          reply_delay_ms: non_neg_integer(),
          password_hint: String.t() | nil,
          qr_link: String.t() | nil,
          session_id: String.t(),
          session_pid: pid(),
          outbound_message_ids: [integer() | String.t()]
        }

  @outbound_message_id_limit 256

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

  @doc "Logs out the authorized TDLib account so another phone number can be paired."
  @spec switch_account(GenServer.server()) :: :ok | {:error, :telegram_unavailable}
  def switch_account(server \\ __MODULE__), do: GenServer.call(server, :switch_account, 20_000)

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
         reply_delay_ms: Keyword.get(opts, :reply_delay_ms, 2_000),
         password_hint: nil,
         qr_link: nil,
         session_id: session_id,
         session_pid: session_pid,
         outbound_message_ids: []
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

  def handle_call(:switch_account, _from, state) do
    case safe_client_call(fn -> log_out(state.client, state.session_id) end) do
      :ok ->
        state =
          state
          |> Map.put(:auth_state, :switching_account)
          |> Map.put(:connection_status, :authenticating)
          |> Map.put(:last_error?, false)
          |> Map.put(:password_hint, nil)
          |> Map.put(:qr_link, nil)
          |> broadcast_snapshot()

        {:reply, :ok, state}

      {:error, :telegram_unavailable} = error ->
        state = state |> Map.put(:last_error?, true) |> broadcast_snapshot()
        {:reply, error, state}
    end
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
    handle_message(event, jid, message, state)
  end

  def handle_info(
        {:ex_gram_message, session_id, jid, message} = event,
        %{session_id: session_id} = state
      )
      when is_map(message) do
    handle_message(event, jid, message, state)
  end

  def handle_info({:ex_gram_message, _other_session, _jid, message}, state)
      when is_map(message) do
    {:noreply, state}
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

  def handle_info(
        {:ex_gram_session, :disconnected, _reason},
        %{auth_state: :switching_account} = state
      ) do
    {:noreply, state |> Map.put(:connection_status, :authenticating) |> broadcast_snapshot()}
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

  def handle_info(
        {:ex_gram_session, :auth, {:status, :closed}},
        %{auth_state: :switching_account} = state
      ) do
    {:noreply, restart_for_new_account(state) |> broadcast_snapshot()}
  end

  def handle_info({:ex_gram_session, :auth, event}, state) do
    {:noreply, event |> apply_auth_event(state) |> broadcast_snapshot()}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp handle_message(event, jid, message, state) do
    if delivered_by_us?(message, state) do
      Logger.debug("Telegram ignored its own delivered reply")
      {:noreply, forget_outbound_message(state, message)}
    else
      dispatch_message(event, jid, state)
    end
  end

  defp dispatch_message(event, jid, state) do
    case state.handler.(event) do
      :ignore ->
        {:noreply, state}

      {:reply, chunks} when is_list(chunks) ->
        {:noreply, deliver(chunks, jid, state)}

      {:error, _reason} ->
        Logger.warning("Telegram message processing failed")
        {:noreply, state}
    end
  end

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

  defp log_out(client, session_id) do
    case client.send_request_sync(session_id, %{"@type" => "logOut"}, timeout_ms: 15_000) do
      {:ok, _response} -> :ok
      :ok -> :ok
      {:error, _reason} = error -> error
      _unexpected -> {:error, :unexpected_response}
    end
  end

  defp restart_for_new_account(state) do
    with :ok <- safe_client_call(fn -> state.client.disconnect(state.session_id) end),
         :ok <- safe_client_call(fn -> state.client.connect(state.session_id) end) do
      state
      |> Map.put(:auth_state, :switching_account)
      |> Map.put(:connection_status, :connecting)
      |> Map.put(:last_error?, false)
    else
      {:error, :telegram_unavailable} ->
        state
        |> disconnected_state()
        |> Map.put(:last_error?, true)
    end
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
      chunks
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, state}, fn {chunk, index}, {:ok, current_state} ->
        case deliver_chunk(chunk, jid, index, current_state) do
          {:ok, message_id} when is_integer(message_id) or is_binary(message_id) ->
            {:cont, {:ok, remember_outbound_message(current_state, message_id)}}

          {:ok, _missing_message_id} ->
            {:cont, {:ok, current_state}}

          {:error, _reason} ->
            {:halt, {:error, current_state}}
        end
      end)

    case result do
      {:ok, new_state} ->
        new_state

      {:error, new_state} ->
        Logger.warning("Telegram reply delivery failed")
        new_state
    end
  end

  defp deliver_chunk(chunk, jid, index, state) do
    with {:ok, config} <- Spectre.Beam.config(ExBlog.Agent),
         {:ok, %Receipt{provider_message_id: message_id}} <-
           Spectre.Beam.deliver(
             config,
             :telegram,
             %{
               conversation_id: jid,
               to: jid,
               content: Content.text(chunk),
               idempotency_key: outbound_id(state.session_id)
             },
             adapter_opts: [client: state.session_pid, module: state.client],
             typing: index == 0,
             reply_delay_ms: if(index == 0, do: state.reply_delay_ms, else: 0)
           ) do
      {:ok, message_id}
    end
  end

  defp outbound_id(session_id) do
    unique = System.unique_integer([:positive, :monotonic])
    "telegram:#{session_id}:#{unique}"
  end

  defp delivered_by_us?(message, state) do
    field(message, :from_me) == true and
      field(message, :id) in state.outbound_message_ids
  end

  defp remember_outbound_message(state, message_id) do
    ids =
      [message_id | state.outbound_message_ids]
      |> Enum.uniq()
      |> Enum.take(@outbound_message_id_limit)

    Map.put(state, :outbound_message_ids, ids)
  end

  defp forget_outbound_message(state, message) do
    Map.update!(state, :outbound_message_ids, &List.delete(&1, field(message, :id)))
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
