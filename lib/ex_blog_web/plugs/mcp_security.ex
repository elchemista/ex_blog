defmodule ExBlogWeb.Plugs.MCPSecurity do
  @moduledoc false

  import Plug.Conn

  alias ExBlog.Config

  @supported_versions ["2025-03-26", "2025-06-18", "2025-11-25"]

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    with :ok <- valid_origin(conn),
         :ok <- valid_protocol_version(conn),
         :ok <- authenticated(conn) do
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

  defp authenticated(conn) do
    expected = Config.fetch_secret!(:mcp_token)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> supplied] ->
        if Plug.Crypto.secure_compare(supplied, expected),
          do: :ok,
          else: {:error, :unauthorized}

      _other ->
        {:error, :unauthorized}
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Bearer realm="ExBlog MCP"))
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
