defmodule ExBlogWeb.Admin.SessionController do
  use ExBlogWeb, :controller

  alias ExBlog.Admin.LoginThrottle
  alias ExBlogWeb.AdminAuth

  def create(conn, params) do
    password = get_in(params, ["admin", "password"])
    requester = {:admin_login, conn.remote_ip}

    case LoginThrottle.allow_attempt(requester) do
      :ok -> authenticate(conn, requester, password)
      {:error, retry_after} -> reject_throttled(conn, retry_after)
    end
  end

  def delete(conn, _params) do
    conn
    |> AdminAuth.log_out()
    |> put_flash(:info, "Sessione amministratore terminata.")
    |> redirect(to: ~p"/admin/login")
  end

  defp authenticate(conn, requester, password) do
    if AdminAuth.authenticate_password(password) do
      LoginThrottle.reset(requester)

      conn = AdminAuth.log_in(conn)
      {conn, destination} = AdminAuth.pop_return_to(conn)

      conn
      |> put_flash(:info, "Accesso effettuato.")
      |> redirect(to: destination)
    else
      conn
      |> put_flash(:error, "Password non valida.")
      |> redirect(to: ~p"/admin/login")
    end
  end

  defp reject_throttled(conn, retry_after) do
    conn
    |> put_flash(:error, "Troppi tentativi. Riprova tra #{retry_after} secondi.")
    |> redirect(to: ~p"/admin/login")
  end
end
