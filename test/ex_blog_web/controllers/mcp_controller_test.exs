defmodule ExBlogWeb.MCPControllerTest do
  use ExBlogWeb.ConnCase, async: false

  test "rejects missing bearer authentication", %{conn: conn} do
    conn = post(conn, "/mcp", request("initialize", %{}, 1))

    assert response(conn, 401)
    assert get_resp_header(conn, "www-authenticate") == [~s(Bearer realm="ExBlog MCP")]
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
      conn
      |> authenticated_conn()
      |> post("/mcp", request("initialize", %{}, 3))

    assert %{
             "result" => %{
               "protocolVersion" => "2025-11-25",
               "serverInfo" => %{"name" => "ExBlog"}
             }
           } = json_response(conn, 200)

    conn =
      build_conn()
      |> authenticated_conn()
      |> post("/mcp", request("tools/list", %{}, 4))

    assert %{"result" => %{"tools" => tools}} = json_response(conn, 200)
    assert Enum.any?(tools, &(&1["name"] == "read_article"))

    delete_tool = Enum.find(tools, &(&1["name"] == "delete_article"))
    assert delete_tool["annotations"]["destructiveHint"]
    refute delete_tool["annotations"]["readOnlyHint"]

    config_tool = Enum.find(tools, &(&1["name"] == "show_config"))
    assert config_tool["annotations"]["readOnlyHint"]

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

  test "GET is authenticated and reports that streaming is unsupported", %{conn: conn} do
    conn = conn |> authenticated_conn() |> get("/mcp")
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

  defp request(method, params, id) do
    %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}
  end
end
