defmodule ExBlog.Telegram.TransportTest do
  use ExUnit.Case, async: false

  alias ExBlog.Telegram.{BeamAdapter, ClientFake, Transport}
  alias Spectre.Beam.Config, as: BeamConfig

  setup do
    session_pid = start_supervised!({Agent, fn -> :session end})
    Application.put_env(:ex_blog, ClientFake, %{session_pid: session_pid, test_pid: self()})

    on_exit(fn -> Application.delete_env(:ex_blog, ClientFake) end)

    %{session_pid: session_pid}
  end

  test "configures Spectre Beam typing with a two-second reply delay" do
    assert {:ok, config} = Spectre.Beam.config(ExBlog.Agent)
    assert {:ok, endpoint} = BeamConfig.fetch(config, :telegram)

    assert endpoint.adapter == BeamAdapter
    assert endpoint.metadata.typing == true
    assert endpoint.metadata.reply_delay_ms == 2_000
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

  test "uses Spectre Beam typing and replies to the message jid", %{session_pid: session_pid} do
    test_pid = self()

    transport =
      start_transport(fn event ->
        send(test_pid, {:handled, event})
        {:reply, ["first", "second"]}
      end)

    event = {:ex_gram_message, "-10042", %{id: 7, sender_id: 42, text: "hello"}}
    send(transport, event)

    assert_receive {:handled, ^event}
    assert_receive {ClientFake, {:send_typing, ^session_pid, "-10042", true}}
    assert_receive {ClientFake, {:send_message, ^session_pid, "-10042", "first"}}
    assert_receive {ClientFake, {:send_message, ^session_pid, "-10042", "second"}}
  end

  test "does not process replies emitted by the application as new commands", %{
    session_pid: session_pid
  } do
    client_config =
      :ex_blog
      |> Application.fetch_env!(ClientFake)
      |> Map.put(:sent_message_id, 901)

    Application.put_env(:ex_blog, ClientFake, client_config)

    test_pid = self()

    transport =
      start_transport(fn event ->
        send(test_pid, {:handled, event})
        {:reply, ["application reply"]}
      end)

    inbound = {:ex_gram_message, "42", %{id: 7, sender_id: 42, text: "hello"}}
    send(transport, inbound)

    assert_receive {:handled, ^inbound}
    assert_receive {ClientFake, {:send_typing, ^session_pid, "42", true}}
    assert_receive {ClientFake, {:send_message, ^session_pid, "42", "application reply"}}

    delivered_reply =
      {:ex_gram_message, "42",
       %{id: 901, from_me: true, sender_id: 42, text: "application reply"}}

    send(transport, delivered_reply)
    _state = :sys.get_state(transport)

    refute_receive {:handled, ^delivered_reply}
  end

  test "accepts session-qualified messages only for its configured session" do
    test_pid = self()

    transport =
      start_transport(fn event ->
        send(test_pid, {:handled, event})
        :ignore
      end)

    matching = {:ex_gram_message, "test_session", "42", %{id: 8, text: "matching"}}
    other = {:ex_gram_message, "another_session", "42", %{id: 9, text: "other"}}

    send(transport, matching)
    send(transport, other)
    _state = :sys.get_state(transport)

    assert_receive {:handled, ^matching}
    refute_receive {:handled, ^other}
  end

  test "projects ExGram authorization events without persisting login inputs" do
    transport = start_transport(fn _event -> :ignore end)

    send(transport, {:ex_gram_session, :auth, {:wait_phone_number}})
    _state = :sys.get_state(transport)

    assert %{
             auth_state: :wait_phone_number,
             connection_status: :authenticating,
             qr_link: nil
           } = Transport.snapshot(transport)

    assert :ok = Transport.request_qr(transport)
    assert_receive {ClientFake, {:request_qr_code_login, "test_session"}}
    assert %{auth_state: :requesting_qr} = Transport.snapshot(transport)

    login_link = "tg://login?token=short-lived"
    send(transport, {:ex_gram_session, :auth, {:wait_other_device_confirmation, login_link}})
    _state = :sys.get_state(transport)

    assert %{auth_state: :wait_other_device_confirmation, qr_link: ^login_link} =
             Transport.snapshot(transport)

    assert :ok = Transport.provide_phone_number("+393331234567", transport)
    assert_receive {ClientFake, {:provide_phone_number, "test_session", "+393331234567"}}

    assert :ok = Transport.provide_auth_code("12345", transport)
    assert_receive {ClientFake, {:provide_auth_code, "test_session", "12345"}}

    assert :ok = Transport.provide_password("telegram-secret", transport)
    assert_receive {ClientFake, {:provide_password, "test_session", "telegram-secret"}}

    send(transport, {:ex_gram_session, :auth, {:status, :ready}})
    _state = :sys.get_state(transport)

    assert %{
             auth_state: :ready,
             connection_status: :connected,
             password_hint: nil,
             qr_link: nil
           } = Transport.snapshot(transport)
  end

  test "logs out the current account before pairing another number" do
    transport = start_transport(fn _event -> :ignore end)

    send(transport, {:ex_gram_session, :auth, {:status, :ready}})
    _state = :sys.get_state(transport)

    assert :ok = Transport.switch_account(transport)

    assert_receive {ClientFake,
                    {:send_request_sync, "test_session", %{"@type" => "logOut"},
                     [timeout_ms: 15_000]}}

    assert %{auth_state: :switching_account, connection_status: :authenticating} =
             Transport.snapshot(transport)

    send(transport, {:ex_gram_session, :disconnected, :authorization_closed})
    _state = :sys.get_state(transport)

    assert %{auth_state: :switching_account, connection_status: :authenticating} =
             Transport.snapshot(transport)

    send(transport, {:ex_gram_session, :auth, {:status, :closed}})
    _state = :sys.get_state(transport)

    assert_receive {ClientFake, {:disconnect, "test_session"}}
    assert_receive {ClientFake, {:connect, "test_session"}}

    assert %{auth_state: :switching_account, connection_status: :connecting} =
             Transport.snapshot(transport)

    send(transport, {:ex_gram_session, :auth, {:wait_phone_number}})
    _state = :sys.get_state(transport)

    assert %{auth_state: :wait_phone_number, connection_status: :authenticating} =
             Transport.snapshot(transport)
  end

  defp start_transport(handler) do
    start_supervised!(
      {Transport,
       name: nil,
       client: ClientFake,
       handler: handler,
       reply_delay_ms: 0,
       session_id: "test_session",
       database_directory: database_directory()}
    )
  end

  defp database_directory do
    Path.join(System.tmp_dir!(), "ex_blog_transport_test")
  end
end
