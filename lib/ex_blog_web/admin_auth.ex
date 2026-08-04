defmodule ExBlogWeb.AdminAuth do
  @moduledoc """
  Password and session authentication for the single administrator area.

  The configured Argon2 hash is fingerprinted into each session so rotating
  `EX_BLOG_ADMIN_PASSWORD_HASH` immediately invalidates existing logins.
  """

  use ExBlogWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias ExBlog.Config

  @authenticated_at_key "admin_authenticated_at"
  @password_fingerprint_key "admin_password_fingerprint"
  @return_to_key "admin_return_to"
  @session_max_age_seconds 8 * 60 * 60
  @max_return_to_bytes 4_096

  @spec authenticate_password(String.t()) :: boolean()
  def authenticate_password(password) when is_binary(password) do
    Argon2.verify_pass(password, Config.fetch_secret!(:admin_password_hash))
  rescue
    _exception -> false
  end

  def authenticate_password(_password) do
    Argon2.no_user_verify()
    false
  end

  @spec log_in(Plug.Conn.t()) :: Plug.Conn.t()
  def log_in(conn) do
    conn
    |> configure_session(renew: true)
    |> put_session(@authenticated_at_key, System.system_time(:second))
    |> put_session(@password_fingerprint_key, password_fingerprint())
  end

  @spec log_out(Plug.Conn.t()) :: Plug.Conn.t()
  def log_out(conn), do: configure_session(conn, drop: true)

  @doc "Consumes the safe local destination remembered before administrator login."
  @spec pop_return_to(Plug.Conn.t()) :: {Plug.Conn.t(), String.t()}
  def pop_return_to(conn) do
    path = get_session(conn, @return_to_key)
    destination = if safe_return_to?(path), do: path, else: ~p"/admin/telegram"
    {delete_session(conn, @return_to_key), destination}
  end

  @spec authenticated?(map()) :: boolean()
  def authenticated?(session) when is_map(session) do
    now = System.system_time(:second)
    authenticated_at = session_value(session, @authenticated_at_key)
    fingerprint = session_value(session, @password_fingerprint_key)

    is_integer(authenticated_at) and authenticated_at <= now and
      now - authenticated_at < @session_max_age_seconds and
      secure_fingerprint?(fingerprint)
  end

  def authenticated?(_session), do: false

  @spec fetch_current_scope(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def fetch_current_scope(conn, _opts) do
    assign(conn, :current_scope, current_scope(get_session(conn)))
  end

  @spec redirect_if_authenticated(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def redirect_if_authenticated(conn, _opts) do
    if conn.assigns.current_scope.admin? do
      conn
      |> redirect(to: ~p"/admin/telegram")
      |> halt()
    else
      conn
    end
  end

  @spec require_authenticated(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def require_authenticated(conn, _opts) do
    if conn.assigns.current_scope.admin? do
      conn
    else
      conn
      |> remember_return_to()
      |> put_flash(:error, "Accedi come amministratore per continuare.")
      |> redirect(to: ~p"/admin/login")
      |> halt()
    end
  end

  @spec put_security_headers(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def put_security_headers(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store, max-age=0")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("x-robots-tag", "noindex, nofollow, noarchive")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("content-security-policy", "frame-ancestors 'none'")
  end

  @doc false
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, Phoenix.Component.assign(socket, :current_scope, current_scope(session))}
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket = Phoenix.Component.assign(socket, :current_scope, current_scope(session))

    if socket.assigns.current_scope.admin? do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/admin/telegram")}
    else
      {:cont, socket}
    end
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = Phoenix.Component.assign(socket, :current_scope, current_scope(session))

    if socket.assigns.current_scope.admin? do
      {:cont, attach_session_expiry(socket, session)}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "Accedi come amministratore per continuare.")
        |> Phoenix.LiveView.redirect(to: ~p"/admin/login")

      {:halt, socket}
    end
  end

  defp current_scope(session) do
    %{
      admin?: authenticated?(session),
      authenticated_at: session_value(session, @authenticated_at_key)
    }
  end

  defp attach_session_expiry(socket, session) do
    if Phoenix.LiveView.connected?(socket) do
      authenticated_at = session_value(session, @authenticated_at_key)

      expires_in_ms =
        max(
          (authenticated_at + @session_max_age_seconds - System.system_time(:second)) * 1_000,
          0
        )

      Process.send_after(self(), {__MODULE__, :session_expired}, expires_in_ms)

      Phoenix.LiveView.attach_hook(
        socket,
        :admin_session_expiry,
        :handle_info,
        &handle_session_expiry/2
      )
    else
      socket
    end
  end

  defp handle_session_expiry({__MODULE__, :session_expired}, socket) do
    socket =
      socket
      |> Phoenix.LiveView.put_flash(:error, "La sessione amministratore è scaduta.")
      |> Phoenix.LiveView.redirect(to: ~p"/admin/login")

    {:halt, socket}
  end

  defp handle_session_expiry(_message, socket), do: {:cont, socket}

  defp session_value(session, @authenticated_at_key) do
    Map.get(session, @authenticated_at_key) || Map.get(session, :admin_authenticated_at)
  end

  defp session_value(session, @password_fingerprint_key) do
    Map.get(session, @password_fingerprint_key) || Map.get(session, :admin_password_fingerprint)
  end

  defp remember_return_to(%Plug.Conn{method: "GET"} = conn) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    destination = conn.request_path <> query

    if safe_return_to?(destination),
      do: put_session(conn, @return_to_key, destination),
      else: conn
  end

  defp remember_return_to(conn), do: conn

  defp safe_return_to?(path) when is_binary(path) do
    byte_size(path) <= @max_return_to_bytes and String.starts_with?(path, "/") and
      not String.starts_with?(path, "//")
  end

  defp safe_return_to?(_path), do: false

  defp secure_fingerprint?(fingerprint) when is_binary(fingerprint) do
    expected = password_fingerprint()

    byte_size(fingerprint) == byte_size(expected) and
      Plug.Crypto.secure_compare(fingerprint, expected)
  end

  defp secure_fingerprint?(_fingerprint), do: false

  defp password_fingerprint do
    :sha256
    |> :crypto.hash(Config.fetch_secret!(:admin_password_hash))
    |> Base.url_encode64(padding: false)
  end
end
