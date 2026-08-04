defmodule ExBlogWeb.Admin.TelegramLiveTest do
  use ExBlogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ExBlog.Telegram.{ClientFake, Transport}
  alias ExBlogWeb.AdminAuth

  setup %{conn: conn} do
    session_pid = start_supervised!({Agent, fn -> :session end})
    Application.put_env(:ex_blog, ClientFake, %{session_pid: session_pid, test_pid: self()})

    start_supervised!(
      {Transport,
       client: ClientFake,
       handler: fn _event -> :ignore end,
       session_id: "admin_live_test",
       database_directory: Path.join(System.tmp_dir!(), "ex_blog_admin_live_test")}
    )

    on_exit(fn -> Application.delete_env(:ex_blog, ClientFake) end)

    conn = conn |> Plug.Test.init_test_session(%{}) |> AdminAuth.log_in()
    %{conn: conn}
  end

  test "renders the protected connection dashboard", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/telegram")

    assert has_element?(view, "#admin-telegram-page")
    assert has_element?(view, "#admin-telegram-heading")
    assert has_element?(view, "#telegram-connection-status")
    assert has_element?(view, "#telegram-session-id", "admin_live_test")
    assert has_element?(view, "#telegram-disconnected-panel")
  end

  test "requests and renders the short-lived ExGram QR link", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/telegram")

    send_snapshot(view, :wait_phone_number, :authenticating)
    assert has_element?(view, "#telegram-pairing-options")
    assert has_element?(view, "#telegram-phone-form")

    view |> element("#telegram-request-qr-button") |> render_click()
    assert_receive {ClientFake, {:request_qr_code_login, "admin_live_test"}}

    send_snapshot(view, :wait_other_device_confirmation, :authenticating,
      qr_link: "tg://login?token=short-lived"
    )

    assert has_element?(view, "#telegram-qr-panel")
    assert has_element?(view, "#telegram-qr-code[role=img] svg")
  end

  test "forwards phone, code, and two-factor inputs only through the transport", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/telegram")

    send_snapshot(view, :wait_phone_number, :authenticating)

    view
    |> form("#telegram-phone-form", telegram_phone: %{phone: "+39 333 123 4567"})
    |> render_submit()

    assert_receive {ClientFake, {:provide_phone_number, "admin_live_test", "+393331234567"}}

    send_snapshot(view, :wait_code, :authenticating)
    assert has_element?(view, "#telegram-code-form")

    view
    |> form("#telegram-code-form", telegram_code: %{code: "12345"})
    |> render_submit()

    assert_receive {ClientFake, {:provide_auth_code, "admin_live_test", "12345"}}

    send_snapshot(view, :wait_password, :authenticating, password_hint: "parola preferita")
    assert has_element?(view, "#telegram-password-form")
    assert has_element?(view, "#telegram-password-hint", "parola preferita")

    view
    |> form("#telegram-password-form", telegram_password: %{password: "telegram-secret"})
    |> render_submit()

    assert_receive {ClientFake, {:provide_password, "admin_live_test", "telegram-secret"}}
  end

  test "lets a connected administrator switch to another phone number", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/telegram")

    send_snapshot(view, :ready, :connected)

    assert has_element?(view, "#telegram-connected-panel")
    assert has_element?(view, "#telegram-switch-account-button")
    refute has_element?(view, "#telegram-phone-form")
    refute has_element?(view, "#telegram-qr-panel")

    view |> element("#telegram-switch-account-button") |> render_click()

    assert_receive {ClientFake,
                    {:send_request_sync, "admin_live_test", %{"@type" => "logOut"},
                     [timeout_ms: 15_000]}}

    assert has_element?(view, "#telegram-switching-account-panel")

    send_snapshot(view, :wait_phone_number, :authenticating)
    assert has_element?(view, "#telegram-phone-form")
  end

  defp send_snapshot(view, auth_state, connection_status, overrides \\ []) do
    snapshot =
      Map.merge(
        %{
          auth_state: auth_state,
          connection_status: connection_status,
          last_error?: false,
          password_hint: nil,
          qr_link: nil,
          session_id: "admin_live_test"
        },
        Map.new(overrides)
      )

    send(view.pid, {:telegram_connection_updated, snapshot})
    _state = :sys.get_state(view.pid)
    :ok
  end
end
