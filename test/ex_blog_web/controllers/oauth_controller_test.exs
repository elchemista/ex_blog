defmodule ExBlogWeb.OAuthControllerTest do
  use ExBlogWeb.ConnCase, async: false

  alias ExBlog.ChatGPT.OAuth
  alias ExBlog.Storage

  @password "correct horse battery staple"
  @redirect_uri "https://chatgpt.com/connector/oauth/ex-blog"
  @verifier String.duplicate("c", 64)

  setup do
    :ok = Storage.clear()
    :ok
  end

  test "publishes protected-resource and authorization-server discovery", %{conn: conn} do
    authorization = get(conn, "/.well-known/oauth-authorization-server")

    assert %{
             "authorization_endpoint" => authorization_endpoint,
             "token_endpoint" => token_endpoint,
             "registration_endpoint" => registration_endpoint,
             "code_challenge_methods_supported" => ["S256"]
           } = json_response(authorization, 200)

    assert authorization_endpoint == "https://localhost/oauth/authorize"
    assert token_endpoint == "https://localhost/oauth/token"
    assert registration_endpoint == "https://localhost/oauth/register"

    protected = get(build_conn(), "/.well-known/oauth-protected-resource/mcp")

    assert %{
             "resource" => "https://localhost/mcp",
             "authorization_servers" => ["https://localhost"],
             "scopes_supported" => scopes
           } = json_response(protected, 200)

    assert "articles:read" in scopes
    assert "articles:write" in scopes
  end

  test "registers a public client and exchanges an approved code", %{conn: conn} do
    registration =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/oauth/register", %{
        "client_name" => "ChatGPT",
        "redirect_uris" => [@redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    assert %{"client_id" => client_id, "token_endpoint_auth_method" => "none"} =
             json_response(registration, 201)

    params = authorization_params(client_id)

    consent =
      registration
      |> recycle()
      |> log_in_admin()
      |> get("/oauth/authorize", params)

    document = consent |> html_response(200) |> LazyHTML.from_document()
    assert one?(document, "#chatgpt-oauth-consent")
    assert one?(document, "#oauth-consent-heading")
    assert one?(document, "#chatgpt-oauth-consent-form")
    assert one?(document, "#oauth-approve-button")
    assert one?(document, "#oauth-deny-button")
    assert Enum.count(LazyHTML.query(document, "#oauth-requested-scopes li")) == 3
    assert get_resp_header(consent, "x-robots-tag") == ["noindex, nofollow, noarchive"]

    approved =
      consent
      |> recycle()
      |> post("/oauth/authorize", %{"oauth" => Map.put(params, "decision", "approve")})

    callback = approved |> get_resp_header("location") |> List.first() |> URI.parse()
    callback_params = URI.decode_query(callback.query)

    assert callback.scheme == "https"
    assert callback.host == "chatgpt.com"
    assert callback_params["state"] == "opaque-state"
    assert is_binary(callback_params["code"])

    token_response =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> post("/oauth/token", %{
        "grant_type" => "authorization_code",
        "code" => callback_params["code"],
        "client_id" => client_id,
        "redirect_uri" => @redirect_uri,
        "code_verifier" => @verifier,
        "resource" => OAuth.resource_url()
      })

    assert %{
             "access_token" => access_token,
             "refresh_token" => refresh_token,
             "expires_in" => 900,
             "token_type" => "Bearer"
           } = json_response(token_response, 200)

    assert String.starts_with?(access_token, "ex_blog_mcp_")
    assert String.starts_with?(refresh_token, "ex_blog_refresh_")
    assert get_resp_header(token_response, "cache-control") == ["no-store"]
  end

  test "remembers the complete OAuth request while the administrator logs in", %{conn: conn} do
    assert {:ok, client} =
             OAuth.register_client(%{
               "client_name" => "ChatGPT",
               "redirect_uris" => [@redirect_uri]
             })

    anonymous = get(conn, "/oauth/authorize", authorization_params(client.client_id))
    assert redirected_to(anonymous) == "/admin/login"

    return_to = get_session(anonymous, "admin_return_to")
    assert String.starts_with?(return_to, "/oauth/authorize?")
    assert return_to =~ "code_challenge="
    assert return_to =~ "state=opaque-state"

    authenticated = anonymous |> recycle() |> log_in_admin()
    assert redirected_to(authenticated) == return_to
    refute get_session(authenticated, "admin_return_to")

    document =
      authenticated
      |> recycle()
      |> get(return_to)
      |> html_response(200)
      |> LazyHTML.from_document()

    assert one?(document, "#chatgpt-oauth-consent-form")
  end

  test "rejects dynamic registration for a callback outside the allowlist", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/oauth/register", %{
        "client_name" => "Unknown client",
        "redirect_uris" => ["https://attacker.example/callback"]
      })

    assert %{"error" => "invalid_request"} = json_response(response, 400)
    assert get_resp_header(response, "cache-control") == ["no-store"]
  end

  test "filters OAuth credentials from Phoenix request logs" do
    filtered =
      Phoenix.Logger.filter_values(%{
        "code" => "authorization-code",
        "code_verifier" => "pkce-verifier",
        "refresh_token" => "refresh-secret",
        "client_id" => "public-client"
      })

    assert filtered["code"] == "[FILTERED]"
    assert filtered["code_verifier"] == "[FILTERED]"
    assert filtered["refresh_token"] == "[FILTERED]"
    assert filtered["client_id"] == "public-client"
  end

  defp authorization_params(client_id) do
    %{
      "response_type" => "code",
      "client_id" => client_id,
      "redirect_uri" => @redirect_uri,
      "scope" => "offline_access articles:read articles:write",
      "code_challenge" => challenge(),
      "code_challenge_method" => "S256",
      "resource" => OAuth.resource_url(),
      "state" => "opaque-state"
    }
  end

  defp log_in_admin(conn) do
    conn
    |> put_req_header("accept", "text/html")
    |> post("/admin/login", %{"admin" => %{"password" => @password}})
  end

  defp challenge do
    :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  end

  defp one?(document, selector), do: document |> LazyHTML.query(selector) |> Enum.count() == 1
end
