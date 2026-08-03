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
    notify({:connect, session_id})
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
end
