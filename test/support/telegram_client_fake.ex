defmodule ExBlog.Telegram.ClientFake do
  @moduledoc false

  def start_link(opts) do
    %{session_pid: session_pid} = notify({:start_link, opts})
    {:ok, session_pid}
  end

  def subscribe(session_id) do
    notify({:subscribe, session_id})
    :ok
  end

  def connect(session_id) do
    config = notify({:connect, session_id})
    maybe_send_auth_event(config, :connect_auth_event)
    :ok
  end

  def status(session_id) do
    config = notify({:status, session_id})
    Map.get(config, :status, :connecting)
  end

  def request_qr_code_login(session_id) do
    config = notify({:request_qr_code_login, session_id})

    case Map.get(config, :qr_link) do
      link when is_binary(link) ->
        send(self(), {:ex_gram_session, :auth, {:wait_other_device_confirmation, link}})
        maybe_schedule_ready(config)

      _missing ->
        :ok
    end

    :ok
  end

  def provide_phone_number(session_id, phone) do
    config = notify({:provide_phone_number, session_id, phone})
    maybe_send_auth_event(config, :phone_auth_event)
    :ok
  end

  def provide_auth_code(session_id, code) do
    config = notify({:provide_auth_code, session_id, code})
    maybe_send_auth_event(config, :code_auth_event)
    :ok
  end

  def provide_password(session_id, password) do
    config = notify({:provide_password, session_id, password})
    maybe_send_auth_event(config, :password_auth_event)
    :ok
  end

  def send_message(session_id, jid, text) do
    notify({:send_message, session_id, jid, text})
    :ok
  end

  defp notify(message) do
    config = Application.fetch_env!(:ex_blog, __MODULE__)
    send(config.test_pid, {__MODULE__, message})
    config
  end

  defp maybe_send_auth_event(config, key) do
    case Map.get(config, key) do
      nil ->
        :ok

      event ->
        _message = send(self(), {:ex_gram_session, :auth, event})
        :ok
    end

    :ok
  end

  defp maybe_schedule_ready(config) do
    case Map.get(config, :qr_ready_after_ms) do
      milliseconds when is_integer(milliseconds) and milliseconds >= 0 ->
        _timer =
          Process.send_after(
            self(),
            {:ex_gram_session, :auth, {:status, :ready}},
            milliseconds
          )

        :ok

      _missing ->
        :ok
    end

    :ok
  end
end
