defmodule ExBlogWeb.MCPControllerTest do
  use ExBlogWeb.ConnCase, async: false

  alias ExBlog.ChatGPT.OAuth
  alias ExBlog.Storage

  @redirect_uri "https://chatgpt.com/connector/oauth/ex-blog-mcp-test"
  @verifier String.duplicate("m", 64)

  setup do
    :ok = Storage.clear()
    :ok
  end

  test "accepts both configured public hosts as exact origins" do
    previous_origins = Application.get_env(:ex_blog, :public_origins)

    Application.put_env(:ex_blog, :public_origins, [
      "https://spectre.elchemista.com",
      "https://spectre-blog.fly.dev"
    ])

    on_exit(fn ->
      if previous_origins do
        Application.put_env(:ex_blog, :public_origins, previous_origins)
      else
        Application.delete_env(:ex_blog, :public_origins)
      end
    end)

    for origin <- ["https://spectre.elchemista.com/", "https://spectre-blog.fly.dev"] do
      conn =
        build_conn()
        |> put_req_header("origin", origin)
        |> post("/mcp", request("initialize", %{}, System.unique_integer([:positive])))

      assert %{"result" => %{"protocolVersion" => "2025-11-25"}} =
               json_response(conn, 200)
    end
  end

  test "allows protocol discovery and returns the tool-level OAuth challenge", %{conn: conn} do
    initialized = post(conn, "/mcp", request("initialize", %{}, 1))

    assert %{"result" => %{"protocolVersion" => "2025-11-25"}} =
             json_response(initialized, 200)

    challenged =
      build_conn()
      |> post(
        "/mcp",
        request("tools/call", %{"name" => "show_config", "arguments" => %{}}, 2)
      )

    assert %{
             "result" => %{
               "isError" => true,
               "structuredContent" => %{
                 "error" => "invalid_token",
                 "required_scope" => "articles:read"
               },
               "_meta" => %{"mcp/www_authenticate" => [challenge]}
             }
           } = json_response(challenged, 200)

    assert challenge =~ "/.well-known/oauth-protected-resource/mcp"
    assert challenge =~ ~s(scope="articles:read")
    assert challenge =~ ~s(error="insufficient_scope")
  end

  test "rejects an invalid Bearer token with protected-resource discovery", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer invalid-token")
      |> post("/mcp", request("initialize", %{}, 2))

    assert %{"error" => "unauthorized"} = json_response(conn, 401)
    [challenge] = get_resp_header(conn, "www-authenticate")
    assert challenge =~ "/.well-known/oauth-protected-resource/mcp"
    assert challenge =~ ~s(error="invalid_token")
  end

  test "rejects a foreign Origin before dispatch", %{conn: conn} do
    conn =
      conn
      |> authenticated_conn()
      |> put_req_header("origin", "https://attacker.example")
      |> post("/mcp", request("tools/list", %{}, 2))

    assert %{"error" => "invalid_origin"} = json_response(conn, 403)
  end

  test "initializes and lists annotated tools", %{conn: conn} do
    conn =
      post(conn, "/mcp", request("initialize", %{}, 3))

    assert %{
             "result" => %{
               "protocolVersion" => "2025-11-25",
               "serverInfo" => %{"name" => "ExBlog"}
             }
           } = json_response(conn, 200)

    conn =
      build_conn()
      |> post("/mcp", request("tools/list", %{}, 4))

    assert %{"result" => %{"tools" => tools}} = json_response(conn, 200)
    assert Enum.any?(tools, &(&1["name"] == "read_article"))

    delete_tool = Enum.find(tools, &(&1["name"] == "delete_article"))
    assert delete_tool["annotations"]["destructiveHint"]
    refute delete_tool["annotations"]["readOnlyHint"]

    assert delete_tool["securitySchemes"] == [
             %{"type" => "oauth2", "scopes" => ["articles:write"]}
           ]

    assert delete_tool["_meta"]["securitySchemes"] == delete_tool["securitySchemes"]

    config_tool = Enum.find(tools, &(&1["name"] == "show_config"))
    assert config_tool["annotations"]["readOnlyHint"]

    system_tool = Enum.find(tools, &(&1["name"] == "system_status"))
    assert system_tool["annotations"]["readOnlyHint"]
    assert system_tool["annotations"]["openWorldHint"]

    assert config_tool["securitySchemes"] == [
             %{"type" => "oauth2", "scopes" => ["articles:read"]}
           ]

    assert config_tool["_meta"]["securitySchemes"] == config_tool["securitySchemes"]

    check_tool = Enum.find(tools, &(&1["name"] == "check_page"))
    assert check_tool["annotations"]["readOnlyHint"]
    assert check_tool["annotations"]["openWorldHint"]

    encoded = Jason.encode!(tools)

    for field <- [:github_token, :openrouter_api_key, :mcp_token, :telegram_api_hash] do
      refute encoded =~ ExBlog.Config.fetch_secret!(field)
    end
  end

  test "calls the shared safe configuration action without exposing credentials", %{conn: conn} do
    conn =
      conn
      |> authenticated_conn()
      |> post(
        "/mcp",
        request("tools/call", %{"name" => "show_config", "arguments" => %{}}, 5)
      )

    assert %{
             "result" => %{
               "isError" => false,
               "structuredContent" => projection
             }
           } = json_response(conn, 200)

    assert projection["github_token"] == "configured"
    assert projection["openrouter_token"] == "configured"

    encoded = Jason.encode!(projection)
    refute encoded =~ ExBlog.Config.fetch_secret!(:github_token)
    refute encoded =~ ExBlog.Config.fetch_secret!(:openrouter_api_key)
    refute encoded =~ ExBlog.Config.fetch_secret!(:mcp_token)
    refute encoded =~ ExBlog.Config.fetch_secret!(:telegram_api_hash)
  end

  test "accepts a persisted OAuth token and enforces its granted scopes", %{conn: conn} do
    access_token = oauth_access_token("articles:read")

    readable =
      conn
      |> oauth_conn(access_token)
      |> post(
        "/mcp",
        request("tools/call", %{"name" => "show_config", "arguments" => %{}}, 7)
      )

    assert %{"result" => %{"isError" => false}} = json_response(readable, 200)

    denied =
      readable
      |> recycle()
      |> oauth_conn(access_token)
      |> post(
        "/mcp",
        request(
          "tools/call",
          %{"name" => "publish_article", "arguments" => %{"lang" => "it", "slug" => "x"}},
          8
        )
      )

    assert %{
             "result" => %{
               "isError" => true,
               "structuredContent" => %{"required_scope" => "articles:write"},
               "_meta" => %{"mcp/www_authenticate" => [_challenge]}
             }
           } = json_response(denied, 200)
  end

  test "GET reports that streaming is unsupported", %{conn: conn} do
    conn = get(conn, "/mcp")
    assert response(conn, 405) == ""
    assert get_resp_header(conn, "allow") == ["POST"]
  end

  test "rejects unsupported protocol versions and accepts initialized notifications", %{
    conn: conn
  } do
    invalid =
      conn
      |> authenticated_conn()
      |> put_req_header("mcp-protocol-version", "2099-01-01")
      |> post("/mcp", request("tools/list", %{}, 6))

    assert %{"error" => "unsupported_protocol_version"} = json_response(invalid, 400)

    notification =
      build_conn()
      |> authenticated_conn()
      |> post("/mcp", %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    assert response(notification, 202) == ""
  end

  defp authenticated_conn(conn) do
    conn
    |> put_req_header("authorization", "Bearer #{ExBlog.Config.fetch_secret!(:mcp_token)}")
    |> put_req_header("accept", "application/json, text/event-stream")
  end

  defp oauth_conn(conn, access_token) do
    conn
    |> put_req_header("authorization", "Bearer #{access_token}")
    |> put_req_header("accept", "application/json, text/event-stream")
  end

  defp oauth_access_token(scope) do
    assert {:ok, client} =
             OAuth.register_client(%{
               "client_name" => "ChatGPT",
               "redirect_uris" => [@redirect_uri]
             })

    challenge = :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)

    assert {:ok, authorization} =
             OAuth.validate_authorization_request(%{
               "response_type" => "code",
               "client_id" => client.client_id,
               "redirect_uri" => @redirect_uri,
               "scope" => scope,
               "code_challenge" => challenge,
               "code_challenge_method" => "S256",
               "resource" => OAuth.resource_url()
             })

    assert {:ok, code} = OAuth.issue_authorization_code(authorization)

    assert {:ok, token} =
             OAuth.exchange_authorization_code(%{
               "grant_type" => "authorization_code",
               "code" => code,
               "client_id" => client.client_id,
               "redirect_uri" => @redirect_uri,
               "code_verifier" => @verifier,
               "resource" => OAuth.resource_url()
             })

    token.access_token
  end

  defp request(method, params, id) do
    %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}
  end
end
