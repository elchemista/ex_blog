defmodule ExBlog.Pulse.Access do
  @moduledoc """
  Authentication and authorization for the `:studio` Pulse connection.

  Pulse calls `authenticate/2` once per WebSocket upgrade with Phoenix's
  transport information as an opaque credential, then `authorize/2` with the
  resulting principal. Pulse discards the credential after the handshake: the
  live connection, its manifest, and every error carry the principal and its
  grants but never the token.

  Authentication proves who owns the socket. Authorization decides what that
  owner may do, and a scope is granted only when it survives all three filters:

    1. `ExBlog.Pulse` allows it on the connection definition;
    2. the authenticated principal owns it;
    3. this authorizer returns it.

  There is one operator credential, the same design as the direct MCP token:
  this blog has a single administrator, so a per-user token store would add a
  moving part without adding a boundary. Rotating `EX_BLOG_PULSE_TOKEN` changes
  the principal id, which makes a rotation visible in Studio and in any log that
  recorded the previous connection.
  """

  alias ExBlog.Config
  alias ExBlog.Pulse
  alias Spectre.Pulse.Principal

  @kind :studio

  @doc """
  Verifies the connection token and returns the Studio operator principal.

  The token arrives as the `token` query parameter, which is the shape Pulse's
  Phoenix guide documents and the one Studio's client sends. It is compared in
  constant time against the configured credential; a deployment without a
  configured token rejects every connection.
  """
  @spec authenticate(map(), map()) :: {:ok, map()} | {:error, atom()}
  def authenticate(transport_info, context) when is_map(transport_info) and is_map(context) do
    config = Config.get()

    with {:ok, token} <- fetch_token(transport_info),
         :ok <- verify_token(token, Config.pulse_token(config)) do
      {:ok, principal(config, context)}
    end
  end

  def authenticate(_transport_info, _context), do: {:error, :invalid_pulse_credential}

  @doc """
  Grants the intersection of the connection definition and the principal.

  The intersection is computed against `ExBlog.Pulse.supported_scopes/0` rather
  than against whatever the request carries, so a scope this deployment cannot
  serve can never reach a manifest — not even if a connection definition were
  later widened by mistake.
  """
  @spec authorize(Principal.t(), map()) :: {:ok, keyword()} | {:error, atom()}
  def authorize(%Principal{} = principal, request) when is_map(request) do
    allowed = request |> get_in([:connection_spec, :scopes]) |> List.wrap()

    granted =
      Enum.filter(Pulse.supported_scopes(), fn scope ->
        scope in allowed and scope in principal.scopes
      end)

    case granted do
      [] -> {:error, :no_pulse_scope_granted}
      granted -> {:ok, granted_scopes: granted, granted_profiles: Pulse.profiles()}
    end
  end

  def authorize(_principal, _request), do: {:error, :invalid_pulse_authorization_request}

  @doc """
  The stable principal id for a token.

  Derived from the credential so that it identifies the credential without
  revealing it, and changes the moment the credential is rotated.
  """
  @spec principal_id(String.t()) :: String.t()
  def principal_id(token) when is_binary(token) do
    fingerprint =
      :sha256
      |> :crypto.hash("ex_blog/pulse/studio:" <> token)
      |> binary_part(0, 8)
      |> Base.url_encode64(padding: false)

    "studio-" <> fingerprint
  end

  @spec principal(Config.t(), map()) :: map()
  defp principal(config, context) do
    %{
      id: principal_id(Config.pulse_token(config)),
      # Studio reflects this address back as the `from` of every envelope it
      # sends, so it must be a canonical Pulse address rather than a label.
      identity: "spectre://studio/operator",
      kind: @kind,
      scopes: Pulse.scopes(config),
      verified: verified(context),
      metadata: %{"application" => "ex_blog"}
    }
  end

  # Only facts the transport established, and only in a JSON-safe shape. A peer
  # address is an observation, never an authorization input.
  @spec verified(map()) :: map()
  defp verified(context) do
    %{"issuer" => "ex_blog", "binding" => to_string(Map.get(context, :binding, "unknown"))}
    |> put_peer(Map.get(context, :peer_data))
  end

  @spec put_peer(map(), term()) :: map()
  defp put_peer(verified, %{address: address}) when is_tuple(address) do
    case :inet.ntoa(address) do
      value when is_list(value) -> Map.put(verified, "peer_ip", List.to_string(value))
      {:error, _reason} -> verified
    end
  end

  defp put_peer(verified, _peer_data), do: verified

  @spec fetch_token(map()) :: {:ok, String.t()} | {:error, atom()}
  defp fetch_token(transport_info) do
    case get_in(transport_info, [:params, "token"]) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _missing -> {:error, :pulse_token_required}
    end
  end

  @spec verify_token(String.t(), String.t() | nil) :: :ok | {:error, atom()}
  defp verify_token(_supplied, nil), do: {:error, :pulse_connection_not_configured}

  defp verify_token(supplied, expected) do
    if byte_size(supplied) == byte_size(expected) and
         Plug.Crypto.secure_compare(supplied, expected) do
      :ok
    else
      {:error, :invalid_pulse_token}
    end
  end
end
