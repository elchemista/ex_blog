defmodule ExBlog.Telegram.TransportTest do
  use ExUnit.Case, async: false

  alias ExBlog.Telegram.ClientFake
  alias ExBlog.Telegram.Transport

  setup do
    session_pid = start_supervised!({Agent, fn -> :session end})
    Application.put_env(:ex_blog, ClientFake, %{session_pid: session_pid, test_pid: self()})

    on_exit(fn -> Application.delete_env(:ex_blog, ClientFake) end)

    %{session_pid: session_pid}
  end

  test "starts, subscribes, and connects the configured ExGram session", %{
    session_pid: session_pid
  } do
    transport = start_transport(fn _event -> :ignore end)

    assert_receive {ClientFake, {:start_link, session_opts}}
    assert session_opts[:session_id] == "test_session"
    assert session_opts[:database_directory] == database_directory()
    assert_receive {ClientFake, {:subscribe, "test_session"}}
    assert_receive {ClientFake, {:connect, "test_session"}}

    assert %{session_pid: ^session_pid, session_id: "test_session"} = :sys.get_state(transport)
  end

  test "processes normalized messages and replies to their jid" do
    test_pid = self()

    transport =
      start_transport(fn event ->
        send(test_pid, {:handled, event})
        {:reply, ["first", "second"]}
      end)

    event = {:ex_gram_message, "-10042", %{id: 7, sender_id: 42, text: "hello"}}
    send(transport, event)

    assert_receive {:handled, ^event}
    assert_receive {ClientFake, {:send_message, "test_session", "-10042", "first"}}
    assert_receive {ClientFake, {:send_message, "test_session", "-10042", "second"}}
  end

  defp start_transport(handler) do
    start_supervised!(
      {Transport,
       name: nil,
       client: ClientFake,
       handler: handler,
       session_id: "test_session",
       database_directory: database_directory()}
    )
  end

  defp database_directory do
    Path.join(System.tmp_dir!(), "ex_blog_transport_test")
  end
end
