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
    with {:ok, normalized_origin} <- normalize_origin(origin),
         true <- normalized_origin in allowed_origins(conn) do
      :ok
    else
      _invalid_or_unlisted -> {:error, :invalid_origin}
    end
  end

  defp allowed_origins(conn) do
    case Application.get_env(:ex_blog, :public_origins, []) do
      origins when is_list(origins) and origins != [] ->
        Enum.flat_map(origins, &normalized_origin_list/1)

      _missing ->
        host = Config.get().phx_host || conn.host
        [{"https", String.downcase(host), 443}, {"http", String.downcase(host), 80}]
    end
  end

  defp normalized_origin_list(origin) do
    case normalize_origin(origin) do
      {:ok, normalized} -> [normalized]
      {:error, :invalid_origin} -> []
    end
  end

  defp normalize_origin(origin) when is_binary(origin) do
    case URI.parse(origin) do
      %URI{
        scheme: scheme,
        host: host,
        port: port,
        path: path,
        query: nil,
        fragment: nil,
        userinfo: nil
      }
      when scheme in ["http", "https"] and is_binary(host) and host != "" and
             path in [nil, "", "/"] ->
        {:ok, {scheme, String.downcase(host), port || default_port(scheme)}}

      _invalid ->
        {:error, :invalid_origin}
    end
  end

  defp normalize_origin(_origin), do: {:error, :invalid_origin}

  defp default_port("https"), do: 443
  defp default_port("http"), do: 80

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
