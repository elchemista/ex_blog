defmodule ExBlogWeb.Admin.TelegramLiveTest do
  use ExBlogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ExBlog.Config
  alias ExBlog.Content
  alias ExBlog.Content.{Git, Index, Sync}
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

  test "refresh pulls a newly published article without blocking the dashboard", %{conn: conn} do
    %{publisher: publisher} = content_repository()
    initial_commit = Index.commit_hash()
    cached = get(build_conn(), "/en")
    {:ok, view, _html} = live(conn, ~p"/admin/telegram")

    publish_article(publisher, "from-github")
    assert {:error, :not_found} = Content.get("en", "from-github")

    :ok = :sys.suspend(Sync)

    try do
      view |> element("#telegram-refresh-button") |> render_click()
      assert has_element?(view, ~s(#telegram-refresh-button[disabled][aria-busy="true"]))
      render_click(view, "refresh", %{})
    after
      :ok = :sys.resume(Sync)
    end

    render_async(view)

    assert {:ok, article} = Content.get("en", "from-github")
    assert article.status == :published
    assert Index.commit_hash() != initial_commit
    assert has_element?(view, "#flash-info", "Status and articles updated from GitHub.")
    assert has_element?(view, ~s|#telegram-refresh-button[aria-busy="false"]:not([disabled])|)

    refreshed = get(build_conn(), "/en")
    assert get_resp_header(refreshed, "etag") != get_resp_header(cached, "etag")

    document =
      build_conn() |> get("/en/from-github") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#article-title") |> LazyHTML.text() =~ "from-github"
  end

  test "a failed refresh keeps indexed articles and clears the loading state", %{conn: conn} do
    %{checkout: checkout} = content_repository()
    initial_commit = Index.commit_hash()
    {:ok, view, _html} = live(conn, ~p"/admin/telegram")

    view |> element("#telegram-refresh-button") |> render_click()
    render_async(view)
    assert has_element?(view, "#flash-info")
    File.rm_rf!(checkout)

    view |> element("#telegram-refresh-button") |> render_click()
    render_async(view)

    assert {:ok, _article} = Content.get("en", "existing")
    assert Index.commit_hash() == initial_commit

    assert has_element?(
             view,
             "#flash-error",
             "Telegram status updated, but articles could not be synchronized. Try again."
           )

    assert has_element?(view, ~s|#telegram-refresh-button[aria-busy="false"]:not([disabled])|)
    refute has_element?(view, "#flash-info")
    refute render(view) =~ Config.fetch_secret!(:github_token)
    refute render(view) =~ "git_repository_not_found"
    assert build_conn() |> get("/en/existing") |> html_response(200)
  end

  defp content_repository do
    root =
      Path.join(System.tmp_dir!(), "ex-blog-admin-sync-#{System.unique_integer([:positive])}")

    origin = Path.join(root, "origin.git")
    publisher = Path.join(root, "publisher")
    previous_config = Config.get()
    File.mkdir_p!(publisher)
    git!(["init", "--bare", origin], root)
    git!(["init", "--initial-branch=main"], publisher)
    git!(["remote", "add", "origin", origin], publisher)
    publish_article(publisher, "existing")

    config =
      Config.test_config(
        data_dir: root,
        default_language: "en",
        git_sync_interval_ms: 60_000
      )

    :ok = Config.install(config)

    on_exit(fn ->
      :ok = Config.install(previous_config)
      File.rm_rf!(root)
    end)

    checkout = Config.repository_path(config)
    assert {:ok, _commit} = Git.clone(config: config, path: checkout, url: origin)
    start_supervised!({Index, root: checkout, content_root: config.content_root})

    start_supervised!(
      {Sync, root: Path.join(root, "public"), durable_root: Path.join(root, "durable")}
    )

    %{publisher: publisher, checkout: checkout}
  end

  defp publish_article(publisher, slug) do
    directory = Path.join(publisher, "content/en")
    File.mkdir_p!(directory)

    File.write!(Path.join(directory, "2026-11-17-#{slug}.md"), """
    ---
    title: Article #{slug}
    slug: #{slug}
    lang: en
    status: published
    date: 2026-11-17
    tags: []
    ---
    Article published in the remote content repository.
    """)

    git!(["add", "."], publisher)
    git!(["commit", "-m", "Publish #{slug}"], publisher)
    git!(["push", "origin", "main"], publisher)
  end

  defp git!(args, directory) do
    env = [
      {"GIT_AUTHOR_NAME", "ExBlog Test"},
      {"GIT_AUTHOR_EMAIL", "test@example.com"},
      {"GIT_COMMITTER_NAME", "ExBlog Test"},
      {"GIT_COMMITTER_EMAIL", "test@example.com"}
    ]

    assert {_output, 0} = System.cmd("git", args, cd: directory, env: env, stderr_to_stdout: true)
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
