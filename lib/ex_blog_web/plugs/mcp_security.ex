defmodule ExBlogWeb.Plugs.MCPSecurity do
  @moduledoc false

  import Plug.Conn

  alias ExBlog.ChatGPT.OAuth
  alias ExBlog.Config

  @supported_versions ["2025-03-26", "2025-06-18", "2025-11-25"]

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    with :ok <- valid_origin(conn),
         :ok <- valid_protocol_version(conn),
         {:ok, conn} <- authenticate(conn) do
      conn
    else
      {:error, :invalid_origin} ->
        reject(conn, :forbidden, "invalid_origin")

      {:error, :unsupported_protocol_version} ->
        reject(conn, :bad_request, "unsupported_protocol_version")

      {:error, :unauthorized} ->
        unauthorized(conn)
    end
  end

  defp valid_origin(conn) do
    case get_req_header(conn, "origin") do
      [] -> :ok
      [origin] -> origin_allowed?(conn, origin)
      _multiple -> {:error, :invalid_origin}
    end
  end

  defp origin_allowed?(conn, origin) do
    uri = URI.parse(origin)
    configured_host = Config.get().phx_host
    allowed_hosts = if configured_host, do: [configured_host], else: [conn.host]

    if uri.scheme in ["http", "https"] and uri.host in allowed_hosts and
         uri.userinfo == nil and uri.query == nil and uri.fragment == nil and
         uri.path in [nil, "", "/"] do
      :ok
    else
      {:error, :invalid_origin}
    end
  end

  defp valid_protocol_version(conn) do
    case get_req_header(conn, "mcp-protocol-version") do
      [] -> :ok
      [version] when version in @supported_versions -> :ok
      _other -> {:error, :unsupported_protocol_version}
    end
  end

  defp authenticate(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> supplied] ->
        authenticate_bearer(conn, supplied)

      [] ->
        {:ok, assign_identity(conn, nil, MapSet.new(), :anonymous)}

      _other ->
        {:error, :unauthorized}
    end
  end

  defp authenticate_bearer(conn, supplied) do
    if static_token?(supplied) do
      principal = %{subject: :admin, client_id: "operator-token"}
      {:ok, assign_identity(conn, principal, MapSet.new(OAuth.allowed_scopes()), :static)}
    else
      case OAuth.authenticate_access_token(supplied) do
        {:ok, principal, scopes} ->
          {:ok, assign_identity(conn, principal, scopes, :oauth)}

        {:error, _reason} ->
          {:error, :unauthorized}
      end
    end
  end

  defp static_token?(supplied) do
    expected = Config.fetch_secret!(:mcp_token)

    byte_size(supplied) == byte_size(expected) and
      Plug.Crypto.secure_compare(supplied, expected)
  end

  defp assign_identity(conn, principal, scopes, method) do
    conn
    |> assign(:mcp_authenticated?, not is_nil(principal))
    |> assign(:mcp_principal, principal)
    |> assign(:mcp_scopes, scopes)
    |> assign(:mcp_auth_method, method)
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header(
      "www-authenticate",
      OAuth.authorization_challenge(nil, "invalid_token", "The Bearer token is invalid")
    )
    |> reject(:unauthorized, "unauthorized")
  end

  defp reject(conn, status, error) do
    body = Jason.encode!(%{error: error})

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, body)
    |> halt()
  end
end
