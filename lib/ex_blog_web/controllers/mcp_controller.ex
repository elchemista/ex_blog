defmodule ExBlogWeb.MCPController do
  use ExBlogWeb, :controller

  alias ExBlog.ChatGPT.OAuth
  alias ExBlogWeb.MCP.Tools

  @protocol_version "2025-11-25"

  def create(conn, request) when is_map(request) do
    case handle_request(request, conn) do
      nil -> send_resp(conn, :accepted, "")
      response -> respond(conn, response)
    end
  end

  def create(conn, _request), do: respond(conn, jsonrpc_error(nil, -32_600, "Invalid Request"))

  def method_not_allowed(conn, _params) do
    conn
    |> put_resp_header("allow", "POST")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(:method_not_allowed, "")
  end

  defp handle_request(%{"jsonrpc" => "2.0", "method" => method} = request, conn) do
    id = Map.get(request, "id")
    params = Map.get(request, "params", %{})

    case method do
      "initialize" ->
        jsonrpc_result(id, %{
          protocolVersion: @protocol_version,
          capabilities: %{tools: %{listChanged: false}},
          serverInfo: %{
            name: "ExBlog",
            version: Application.spec(:ex_blog, :vsn) |> to_string(),
            description: "Authenticated editorial operations for ExBlog"
          },
          instructions:
            "Read before editing. Ask for explicit confirmation before writes, publication, unpublication, or deletion. Never request credentials."
        })

      "notifications/initialized" ->
        nil

      "ping" ->
        jsonrpc_result(id, %{})

      "tools/list" ->
        jsonrpc_result(id, %{tools: Tools.list()})

      "tools/call" ->
        tool_call(id, params, conn)

      _method ->
        if Map.has_key?(request, "id"), do: jsonrpc_error(id, -32_601, "Method not found")
    end
  end

  defp handle_request(%{"jsonrpc" => "2.0"}, _conn), do: nil

  defp handle_request(%{"id" => id}, _conn),
    do: jsonrpc_error(id, -32_600, "Invalid Request")

  defp handle_request(_request, _conn), do: jsonrpc_error(nil, -32_600, "Invalid Request")

  defp tool_call(id, %{"name" => name} = params, conn) when is_binary(name) do
    arguments = Map.get(params, "arguments", %{})

    if is_map(arguments) do
      result = authorized_tool_result(conn, name, arguments)

      jsonrpc_result(id, result)
    else
      jsonrpc_error(id, -32_602, "Invalid params")
    end
  end

  defp tool_call(id, _params, _conn), do: jsonrpc_error(id, -32_602, "Invalid params")

  defp authorized_tool_result(conn, name, arguments) do
    case Tools.required_scope(name) do
      {:ok, scope} ->
        if MapSet.member?(conn.assigns.mcp_scopes, scope) do
          execute_tool(name, arguments)
        else
          authentication_required_result(scope)
        end

      :error ->
        execute_tool(name, arguments)
    end
  end

  defp execute_tool(name, arguments) do
    case Tools.call(name, arguments) do
      {:ok, value} -> successful_tool_result(value)
      {:error, reason} -> failed_tool_result(reason)
    end
  end

  defp authentication_required_result(scope) do
    challenge =
      OAuth.authorization_challenge(
        scope,
        "insufficient_scope",
        "Authorize the ExBlog connection to use this tool"
      )

    %{
      content: [%{type: "text", text: "Authentication is required for this tool."}],
      structuredContent: %{ok: false, error: "invalid_token", required_scope: scope},
      isError: true,
      _meta: %{"mcp/www_authenticate" => [challenge]}
    }
  end

  defp successful_tool_result(value) do
    %{
      content: [%{type: "text", text: Jason.encode!(value)}],
      structuredContent: value,
      isError: false
    }
  end

  defp failed_tool_result(reason) do
    {code, message} = safe_error(reason)
    details = %{ok: false, error: code}

    %{
      content: [%{type: "text", text: message}],
      structuredContent: details,
      isError: true
    }
  end

  defp safe_error(:tool_not_found), do: {"tool_not_found", "The requested tool does not exist."}
  defp safe_error(:not_found), do: {"not_found", "The requested article was not found."}

  defp safe_error(:article_identifier_required),
    do: {"invalid_arguments", "lang and slug are required."}

  defp safe_error(:target_language_required),
    do: {"invalid_arguments", "target_lang is required."}

  defp safe_error(:unsupported_language),
    do: {"invalid_arguments", "The language is not supported."}

  defp safe_error({:missing_field, _field}),
    do: {"invalid_arguments", "A required field is missing."}

  defp safe_error(:monthly_budget_exceeded),
    do: {"budget_exceeded", "The configured monthly LLM budget would be exceeded."}

  defp safe_error(:article_budget_exceeded),
    do: {"article_cost_exceeded", "The article cost limit would be exceeded."}

  defp safe_error(_reason), do: {"tool_failed", "The tool could not complete the request."}

  defp jsonrpc_result(id, result), do: %{jsonrpc: "2.0", id: id, result: result}

  defp jsonrpc_error(id, code, message) do
    %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
  end

  defp respond(conn, body) do
    conn
    |> put_resp_header("mcp-protocol-version", @protocol_version)
    |> put_resp_header("cache-control", "no-store")
    |> json(body)
  end
end
