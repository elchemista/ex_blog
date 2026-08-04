defmodule ExBlog.ChatGPT.OAuth do
  @moduledoc """
  OAuth 2.1 authorization server for the ChatGPT MCP connection.

  ExBlog is intentionally database-free, so dynamic clients, one-time codes,
  and token hashes share the durable `ExBlog.Storage` DETS file. Plaintext
  authorization codes, access tokens, and refresh tokens are returned only to
  the OAuth client and are never persisted or written to Git.

  The implementation uses authorization code with PKCE (`S256`), short-lived
  access tokens, rotating refresh tokens, exact resource binding, and an
  allowlist for ChatGPT/OpenAI callback hosts.
  """

  alias ExBlog.Config
  alias ExBlog.Storage

  @storage_key {:chatgpt_oauth, :state}
  @state_version 1

  @read_scope "articles:read"
  @write_scope "articles:write"
  @allowed_scopes ["offline_access", @read_scope, @write_scope]

  @code_ttl_seconds 300
  @access_ttl_seconds 900
  @refresh_ttl_seconds 2_592_000
  @redirect_host_suffixes [".chatgpt.com", ".openai.com"]

  @type scope :: String.t()
  @type token_response :: %{
          required(:access_token) => String.t(),
          required(:token_type) => String.t(),
          required(:expires_in) => pos_integer(),
          required(:refresh_token) => String.t(),
          required(:scope) => String.t(),
          required(:resource) => String.t()
        }

  @doc "OAuth scopes accepted by the authorization server."
  @spec allowed_scopes() :: [scope()]
  def allowed_scopes, do: @allowed_scopes

  @doc "Scope required by MCP tools that only inspect state."
  @spec read_scope() :: String.t()
  def read_scope, do: @read_scope

  @doc "Scope required by MCP tools that mutate state or content."
  @spec write_scope() :: String.t()
  def write_scope, do: @write_scope

  @doc "Canonical public origin used as the OAuth issuer."
  @spec public_base_url() :: String.t()
  def public_base_url do
    :ex_blog
    |> Application.get_env(:chatgpt_public_base_url, Config.canonical_url())
    |> String.trim_trailing("/")
  end

  @doc "Canonical protected-resource identifier for the MCP endpoint."
  @spec resource_url() :: String.t()
  def resource_url, do: public_base_url() <> "/mcp"

  @doc "Discovery URL advertised in HTTP and tool-level challenges."
  @spec resource_metadata_url() :: String.t()
  def resource_metadata_url do
    public_base_url() <> "/.well-known/oauth-protected-resource/mcp"
  end

  @doc "RFC 8414 authorization-server discovery document."
  @spec authorization_server_metadata() :: map()
  def authorization_server_metadata do
    base = public_base_url()

    %{
      issuer: base,
      authorization_endpoint: base <> "/oauth/authorize",
      token_endpoint: base <> "/oauth/token",
      registration_endpoint: base <> "/oauth/register",
      revocation_endpoint: base <> "/oauth/revoke",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"],
      scopes_supported: @allowed_scopes
    }
  end

  @doc "RFC 9728 metadata for the protected MCP resource."
  @spec protected_resource_metadata() :: map()
  def protected_resource_metadata do
    %{
      resource: resource_url(),
      authorization_servers: [public_base_url()],
      scopes_supported: @allowed_scopes,
      bearer_methods_supported: ["header"]
    }
  end

  @doc "Formats the Bearer challenge understood by MCP clients."
  @spec authorization_challenge(scope() | nil, String.t() | nil, String.t() | nil) ::
          String.t()
  def authorization_challenge(scope \\ nil, error \\ nil, description \\ nil) do
    [
      {"resource_metadata", resource_metadata_url()},
      {"scope", scope},
      {"error", error},
      {"error_description", description}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map_join(", ", fn {key, value} -> ~s(#{key}="#{header_value(value)}") end)
    |> then(&("Bearer " <> &1))
  end

  @doc "Registers one public OAuth client through dynamic client registration."
  @spec register_client(map()) :: {:ok, map()} | {:error, term()}
  def register_client(params) when is_map(params) do
    with {:ok, redirect_uris} <- validate_redirect_uris(map_value(params, :redirect_uris)),
         {:ok, client_name} <- client_name(params),
         :ok <- validate_registration_values(params) do
      client_id = random_token("ex_blog_client_")
      issued_at = now()

      client = %{
        client_id: client_id,
        client_name: client_name,
        redirect_uris: redirect_uris,
        grant_types: ["authorization_code", "refresh_token"],
        response_types: ["code"],
        token_endpoint_auth_method: "none",
        issued_at: issued_at
      }

      Storage.update(@storage_key, empty_state(), fn stored ->
        state = stored |> normalize_state() |> prune_state(issued_at)
        next = %{state | clients: Map.put(state.clients, client_id, client)}
        {:put, next, {:ok, client_response(client)}}
      end)
    end
  end

  def register_client(_params), do: {:error, :invalid_client_metadata}

  @doc "Validates an authorization request before showing admin consent."
  @spec validate_authorization_request(map()) :: {:ok, map()} | {:error, term()}
  def validate_authorization_request(params) when is_map(params) do
    with {:ok, client_id} <- required_string(params, :client_id),
         {:ok, client} <- fetch_client(client_id),
         {:ok, redirect_uri} <- required_string(params, :redirect_uri),
         :ok <- validate_client_redirect(client, redirect_uri),
         :ok <- expect_value(params, :response_type, "code"),
         {:ok, code_challenge} <- required_string(params, :code_challenge),
         :ok <- validate_code_challenge(code_challenge),
         :ok <- expect_value(params, :code_challenge_method, "S256"),
         {:ok, resource} <- required_string(params, :resource),
         :ok <- validate_resource(resource),
         {:ok, scopes} <- normalize_scopes(map_value(params, :scope)),
         {:ok, state} <- optional_state(params) do
      {:ok,
       %{
         client_id: client.client_id,
         client_name: client.client_name,
         redirect_uri: redirect_uri,
         resource: resource,
         scopes: scopes,
         scope: Enum.join(scopes, " "),
         code_challenge: code_challenge,
         state: state
       }}
    end
  end

  def validate_authorization_request(_params), do: {:error, :invalid_request}

  @doc "Issues a five-minute, single-use authorization code after admin consent."
  @spec issue_authorization_code(map()) :: {:ok, String.t()} | {:error, term()}
  def issue_authorization_code(%{
        client_id: client_id,
        redirect_uri: redirect_uri,
        resource: resource,
        scopes: scopes,
        code_challenge: code_challenge
      })
      when is_binary(client_id) and is_binary(redirect_uri) and is_binary(resource) and
             is_list(scopes) and is_binary(code_challenge) do
    plaintext = random_token("ex_blog_code_")
    issued_at = now()
    code_hash = hash_token(plaintext)

    record = %{
      client_id: client_id,
      redirect_uri: redirect_uri,
      resource: resource,
      scopes: scopes,
      code_challenge: code_challenge,
      expires_at: issued_at + @code_ttl_seconds
    }

    Storage.update(@storage_key, empty_state(), fn stored ->
      state = stored |> normalize_state() |> prune_state(issued_at)
      store_authorization_code(state, client_id, redirect_uri, code_hash, record, plaintext)
    end)
  end

  def issue_authorization_code(_request), do: {:error, :invalid_request}

  @doc "Consumes an authorization code and returns renewable Bearer credentials."
  @spec exchange_authorization_code(map()) :: {:ok, token_response()} | {:error, term()}
  def exchange_authorization_code(params) when is_map(params) do
    with :ok <- expect_value(params, :grant_type, "authorization_code"),
         {:ok, plaintext_code} <- required_string(params, :code),
         :ok <- validate_opaque_token(plaintext_code, "ex_blog_code_"),
         {:ok, client_id} <- required_string(params, :client_id),
         {:ok, redirect_uri} <- required_string(params, :redirect_uri),
         {:ok, verifier} <- required_string(params, :code_verifier),
         :ok <- validate_code_verifier(verifier),
         {:ok, resource} <- required_string(params, :resource),
         :ok <- validate_resource(resource) do
      exchange_code(plaintext_code, client_id, redirect_uri, verifier, resource)
    end
  end

  def exchange_authorization_code(_params), do: {:error, :invalid_request}

  @doc "Rotates a refresh token and invalidates the complete previous token pair."
  @spec refresh_access_token(map()) :: {:ok, token_response()} | {:error, term()}
  def refresh_access_token(params) when is_map(params) do
    with :ok <- expect_value(params, :grant_type, "refresh_token"),
         {:ok, refresh_token} <- required_string(params, :refresh_token),
         :ok <- validate_opaque_token(refresh_token, "ex_blog_refresh_"),
         {:ok, client_id} <- required_string(params, :client_id),
         {:ok, resource} <- required_string(params, :resource),
         :ok <- validate_resource(resource) do
      rotate_refresh_token(
        refresh_token,
        client_id,
        resource,
        map_value(params, :scope)
      )
    end
  end

  def refresh_access_token(_params), do: {:error, :invalid_request}

  @doc "Authenticates an MCP Bearer token and updates its last-used timestamp."
  @spec authenticate_access_token(String.t()) ::
          {:ok, map(), MapSet.t(scope())} | {:error, term()}
  def authenticate_access_token(plaintext) when is_binary(plaintext) do
    access_hash = hash_token(plaintext)
    checked_at = now()

    Storage.update(@storage_key, empty_state(), fn stored ->
      state = stored |> normalize_state() |> prune_state(checked_at)

      case Map.fetch(state.tokens, access_hash) do
        {:ok, token} -> authenticate_stored_token(state, access_hash, token, checked_at)
        :error -> {:keep, {:error, :invalid_token}}
      end
    end)
  end

  def authenticate_access_token(_plaintext), do: {:error, :invalid_token}

  @doc "Revokes an access or refresh token without revealing whether it existed."
  @spec revoke(String.t()) :: :ok | {:error, term()}
  def revoke(plaintext) when is_binary(plaintext) do
    supplied_hash = hash_token(plaintext)
    revoked_at = now()

    Storage.update(@storage_key, empty_state(), fn stored ->
      state = stored |> normalize_state() |> prune_state(revoked_at)

      tokens =
        Map.new(
          state.tokens,
          &revoke_token_record(&1, supplied_hash, revoked_at)
        )

      {:put, %{state | tokens: tokens}, :ok}
    end)
  end

  def revoke(_plaintext), do: :ok

  defp store_authorization_code(
         state,
         client_id,
         redirect_uri,
         code_hash,
         record,
         plaintext
       ) do
    case Map.fetch(state.clients, client_id) do
      {:ok, client} ->
        put_authorization_code(state, client, redirect_uri, code_hash, record, plaintext)

      :error ->
        {:keep, {:error, :invalid_client}}
    end
  end

  defp put_authorization_code(state, client, redirect_uri, code_hash, record, plaintext) do
    if redirect_uri in client.redirect_uris do
      next = %{state | codes: Map.put(state.codes, code_hash, record)}
      {:put, next, {:ok, plaintext}}
    else
      {:keep, {:error, :invalid_redirect_uri}}
    end
  end

  defp revoke_token_record({access_hash, token}, supplied_hash, revoked_at) do
    matches? =
      secure_hash_match?(access_hash, supplied_hash) or
        secure_hash_match?(token.refresh_token_hash, supplied_hash)

    if matches?,
      do: {access_hash, Map.put(token, :revoked_at, revoked_at)},
      else: {access_hash, token}
  end

  defp exchange_code(plaintext_code, client_id, redirect_uri, verifier, resource) do
    code_hash = hash_token(plaintext_code)
    exchanged_at = now()

    Storage.update(@storage_key, empty_state(), fn stored ->
      state = stored |> normalize_state() |> prune_state(exchanged_at)

      with {:ok, code} <- fetch_record(state.codes, code_hash, :invalid_grant),
           :ok <- match_value(code.client_id, client_id, :invalid_client),
           :ok <- match_value(code.redirect_uri, redirect_uri, :invalid_grant),
           :ok <- match_value(code.resource, resource, :invalid_target),
           :ok <- verify_pkce(code.code_challenge, verifier) do
        {access_hash, token, response} =
          build_token(client_id, resource, code.scopes, exchanged_at)

        next = %{
          state
          | codes: Map.delete(state.codes, code_hash),
            tokens: Map.put(state.tokens, access_hash, token)
        }

        {:put, next, {:ok, response}}
      else
        {:error, _reason} = error -> {:keep, error}
      end
    end)
  end

  defp rotate_refresh_token(refresh_token, client_id, resource, requested_scope) do
    refresh_hash = hash_token(refresh_token)
    rotated_at = now()

    Storage.update(@storage_key, empty_state(), fn stored ->
      state = stored |> normalize_state() |> prune_state(rotated_at)

      with {:ok, access_hash, token} <- find_refresh_token(state.tokens, refresh_hash),
           :ok <- usable_refresh_token?(token, rotated_at),
           :ok <- match_value(token.client_id, client_id, :invalid_client),
           :ok <- match_value(token.resource, resource, :invalid_target),
           {:ok, scopes} <- refresh_scopes(token.scopes, requested_scope) do
        {new_access_hash, new_token, response} =
          build_token(client_id, resource, scopes, rotated_at)

        revoked = Map.put(token, :revoked_at, rotated_at)

        tokens =
          state.tokens
          |> Map.put(access_hash, revoked)
          |> Map.put(new_access_hash, new_token)

        {:put, %{state | tokens: tokens}, {:ok, response}}
      else
        {:error, _reason} = error -> {:keep, error}
      end
    end)
  end

  defp authenticate_stored_token(state, access_hash, token, checked_at) do
    cond do
      not is_nil(token.revoked_at) ->
        {:keep, {:error, :invalid_token}}

      token.access_expires_at <= checked_at ->
        {:keep, {:error, :expired_token}}

      token.resource != resource_url() ->
        {:keep, {:error, :invalid_target}}

      true ->
        touched = Map.put(token, :last_used_at, checked_at)
        next = %{state | tokens: Map.put(state.tokens, access_hash, touched)}
        principal = %{subject: :admin, client_id: token.client_id}
        {:put, next, {:ok, principal, MapSet.new(token.scopes)}}
    end
  end

  defp build_token(client_id, resource, scopes, issued_at) do
    access_token = random_token("ex_blog_mcp_")
    refresh_token = random_token("ex_blog_refresh_")
    access_hash = hash_token(access_token)

    record = %{
      access_token_hash: access_hash,
      refresh_token_hash: hash_token(refresh_token),
      client_id: client_id,
      resource: resource,
      scopes: scopes,
      access_expires_at: issued_at + @access_ttl_seconds,
      refresh_expires_at: issued_at + @refresh_ttl_seconds,
      last_used_at: nil,
      revoked_at: nil
    }

    response = %{
      access_token: access_token,
      token_type: "Bearer",
      expires_in: @access_ttl_seconds,
      refresh_token: refresh_token,
      scope: Enum.join(scopes, " "),
      resource: resource
    }

    {access_hash, record, response}
  end

  defp fetch_client(client_id) do
    case Storage.fetch(@storage_key) do
      {:ok, stored} ->
        stored
        |> normalize_state()
        |> Map.fetch!(:clients)
        |> fetch_record(client_id, :invalid_client)

      :error ->
        {:error, :invalid_client}
    end
  end

  defp fetch_record(records, key, error) do
    case Map.fetch(records, key) do
      {:ok, record} -> {:ok, record}
      :error -> {:error, error}
    end
  end

  defp find_refresh_token(tokens, refresh_hash) do
    case Enum.find(tokens, fn {_access_hash, token} ->
           secure_hash_match?(token.refresh_token_hash, refresh_hash)
         end) do
      {access_hash, token} -> {:ok, access_hash, token}
      nil -> {:error, :invalid_grant}
    end
  end

  defp usable_refresh_token?(token, checked_at) do
    cond do
      not is_nil(token.revoked_at) -> {:error, :invalid_grant}
      token.refresh_expires_at <= checked_at -> {:error, :invalid_grant}
      true -> :ok
    end
  end

  defp verify_pkce(challenge, verifier) do
    calculated = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    if byte_size(challenge) == byte_size(calculated) and
         Plug.Crypto.secure_compare(challenge, calculated) do
      :ok
    else
      {:error, :invalid_grant}
    end
  end

  defp validate_code_challenge(challenge) do
    if byte_size(challenge) == 43 and Regex.match?(~r/^[A-Za-z0-9_-]+$/, challenge),
      do: :ok,
      else: {:error, :invalid_request}
  end

  defp validate_code_verifier(verifier) do
    if byte_size(verifier) in 43..128 and Regex.match?(~r/^[A-Za-z0-9._~-]+$/, verifier),
      do: :ok,
      else: {:error, :invalid_grant}
  end

  defp validate_opaque_token(value, prefix) do
    if byte_size(value) <= 256 and String.starts_with?(value, prefix),
      do: :ok,
      else: {:error, :invalid_grant}
  end

  defp refresh_scopes(existing, nil), do: {:ok, existing}
  defp refresh_scopes(existing, ""), do: {:ok, existing}

  defp refresh_scopes(existing, requested) do
    with {:ok, scopes} <- normalize_scopes(requested),
         true <- MapSet.subset?(MapSet.new(scopes), MapSet.new(existing)) do
      {:ok, scopes}
    else
      _value -> {:error, :invalid_scope}
    end
  end

  defp normalize_scopes(nil), do: {:ok, @allowed_scopes}
  defp normalize_scopes(""), do: {:ok, @allowed_scopes}

  defp normalize_scopes(scope) when is_binary(scope) and byte_size(scope) <= 1_024 do
    scopes = scope |> String.split(~r/\s+/, trim: true) |> Enum.uniq()

    if scopes != [] and Enum.all?(scopes, &(&1 in @allowed_scopes)),
      do: {:ok, scopes},
      else: {:error, :invalid_scope}
  end

  defp normalize_scopes(_scope), do: {:error, :invalid_scope}

  defp validate_registration_values(params) do
    grant_types = map_value(params, :grant_types) || ["authorization_code", "refresh_token"]
    response_types = map_value(params, :response_types) || ["code"]
    auth_method = map_value(params, :token_endpoint_auth_method) || "none"

    with :ok <- validate_grant_types(grant_types),
         :ok <- match_value(response_types, ["code"], :invalid_client_metadata) do
      match_value(auth_method, "none", :invalid_client_metadata)
    end
  end

  defp validate_grant_types(grant_types) when is_list(grant_types) and grant_types != [] do
    if Enum.all?(grant_types, &(&1 in ["authorization_code", "refresh_token"])),
      do: :ok,
      else: {:error, :invalid_client_metadata}
  end

  defp validate_grant_types(_grant_types), do: {:error, :invalid_client_metadata}

  defp client_name(params) do
    with {:ok, value} <- required_string(params, :client_name),
         true <- String.length(value) <= 200 do
      {:ok, value}
    else
      _value -> {:error, :invalid_client_metadata}
    end
  end

  defp validate_redirect_uris(uris) when is_list(uris) and uris != [] and length(uris) <= 10 do
    if Enum.all?(uris, &valid_redirect_uri?/1),
      do: {:ok, Enum.uniq(uris)},
      else: {:error, :invalid_redirect_uri}
  end

  defp validate_redirect_uris(_uris), do: {:error, :invalid_redirect_uri}

  defp valid_redirect_uri?(value) when is_binary(value) and byte_size(value) <= 2_048 do
    case URI.parse(value) do
      %URI{scheme: "https", host: host, userinfo: nil, fragment: nil, port: port}
      when is_binary(host) and port in [nil, 443] ->
        allowed_redirect_host?(host)

      _uri ->
        false
    end
  end

  defp valid_redirect_uri?(_value), do: false

  defp allowed_redirect_host?(host) do
    normalized = String.downcase(host)

    redirect_host_suffixes()
    |> Enum.any?(fn suffix ->
      bare = String.trim_leading(suffix, ".")
      normalized == bare or String.ends_with?(normalized, suffix)
    end)
  end

  defp redirect_host_suffixes do
    Application.get_env(
      :ex_blog,
      :chatgpt_oauth_redirect_host_suffixes,
      @redirect_host_suffixes
    )
  end

  defp validate_client_redirect(client, redirect_uri) do
    if redirect_uri in client.redirect_uris,
      do: :ok,
      else: {:error, :invalid_redirect_uri}
  end

  defp validate_resource(resource), do: match_value(resource_url(), resource, :invalid_target)

  defp optional_state(params) do
    case map_value(params, :state) do
      nil -> {:ok, nil}
      value when is_binary(value) and byte_size(value) <= 1_024 -> {:ok, value}
      _value -> {:error, :invalid_request}
    end
  end

  defp expect_value(params, key, expected) do
    match_value(map_value(params, key), expected, :invalid_request)
  end

  defp match_value(value, value, _error), do: :ok
  defp match_value(_actual, _expected, error), do: {:error, error}

  defp required_string(params, key) do
    case map_value(params, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: {:error, :invalid_request}, else: {:ok, value}

      _value ->
        {:error, :invalid_request}
    end
  end

  defp map_value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp random_token(prefix) do
    prefix <> (:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false))
  end

  defp hash_token(token), do: :crypto.hash(:sha256, token)

  defp secure_hash_match?(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  defp secure_hash_match?(_left, _right), do: false

  defp client_response(client) do
    %{
      client_id: client.client_id,
      client_id_issued_at: client.issued_at,
      client_name: client.client_name,
      redirect_uris: client.redirect_uris,
      grant_types: client.grant_types,
      response_types: client.response_types,
      token_endpoint_auth_method: client.token_endpoint_auth_method
    }
  end

  defp empty_state do
    %{version: @state_version, clients: %{}, codes: %{}, tokens: %{}}
  end

  defp normalize_state(%{
         version: @state_version,
         clients: clients,
         codes: codes,
         tokens: tokens
       })
       when is_map(clients) and is_map(codes) and is_map(tokens) do
    %{version: @state_version, clients: clients, codes: codes, tokens: tokens}
  end

  defp normalize_state(_stored), do: empty_state()

  defp prune_state(state, timestamp) do
    codes = Map.filter(state.codes, fn {_hash, code} -> code.expires_at > timestamp end)

    tokens =
      Map.filter(state.tokens, fn {_access_hash, token} ->
        token.refresh_expires_at > timestamp
      end)

    %{state | codes: codes, tokens: tokens}
  end

  defp header_value(value) do
    value
    |> to_string()
    |> String.replace(["\\", "\"", "\r", "\n"], fn
      "\\" -> "\\\\"
      "\"" -> "\\\""
      _line_break -> ""
    end)
  end

  defp now, do: System.system_time(:second)
end
