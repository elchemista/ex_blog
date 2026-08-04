defmodule ExBlogWeb.AdminAuthTest do
  use ExBlogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ExBlog.Admin.LoginThrottle

  @password "correct horse battery staple"
  @requester {:admin_login, {127, 0, 0, 1}}

  setup do
    LoginThrottle.reset(@requester)
    :ok
  end

  test "the login page is private, uncached, and exposes only the password form", %{conn: conn} do
    conn = get(conn, ~p"/admin/login")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert one?(document, "#admin-login-page")
    assert one?(document, "#admin-login-heading")
    assert one?(document, "#admin-login-form input[type=password]")
    assert one?(document, "#admin-login-submit")

    assert LazyHTML.attribute(LazyHTML.query(document, "meta[name=robots]"), "content") ==
             ["noindex,nofollow,noarchive"]

    assert get_resp_header(conn, "cache-control") == ["no-store, max-age=0"]
    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow, noarchive"]
    assert get_resp_header(conn, "x-frame-options") == ["DENY"]
  end

  test "an anonymous visitor is redirected away from the Telegram page", %{conn: conn} do
    conn = get(conn, ~p"/admin/telegram")

    assert redirected_to(conn) == ~p"/admin/login"
    # The browser pipeline resolves the configured default language, so the
    # English source string is served through its Gettext translation.
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Accedi come amministratore"
  end

  test "a valid Argon2 password creates an administrator session", %{conn: conn} do
    conn = post(conn, ~p"/admin/login", %{"admin" => %{"password" => @password}})

    assert redirected_to(conn) == ~p"/admin/telegram"
    assert is_integer(get_session(conn, "admin_authenticated_at"))
    assert is_binary(get_session(conn, "admin_password_fingerprint"))

    {:ok, view, _html} = conn |> recycle() |> live(~p"/admin/telegram")
    assert has_element?(view, "#admin-telegram-page")
    assert has_element?(view, "#admin-logout-link")
  end

  test "an invalid password does not create a session", %{conn: conn} do
    conn = post(conn, ~p"/admin/login", %{"admin" => %{"password" => "wrong-password"}})

    assert redirected_to(conn) == ~p"/admin/login"
    refute get_session(conn, "admin_authenticated_at")
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Password non valida."
  end

  test "logout drops the administrator session", %{conn: conn} do
    conn = post(conn, ~p"/admin/login", %{"admin" => %{"password" => @password}})
    conn = delete(recycle(conn), ~p"/admin/logout")

    assert redirected_to(conn) == ~p"/admin/login"

    conn = conn |> recycle() |> get(~p"/admin/telegram")
    assert redirected_to(conn) == ~p"/admin/login"
  end

  defp one?(document, selector) do
    document
    |> LazyHTML.query(selector)
    |> Enum.count()
    |> Kernel.==(1)
  end
end
