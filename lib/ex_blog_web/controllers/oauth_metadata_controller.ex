defmodule ExBlogWeb.OAuthMetadataController do
  @moduledoc "OAuth discovery documents consumed by remote MCP clients."

  use ExBlogWeb, :controller

  alias ExBlog.ChatGPT.OAuth

  def protected_resource(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=300")
    |> json(OAuth.protected_resource_metadata())
  end

  def authorization_server(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=300")
    |> json(OAuth.authorization_server_metadata())
  end
end
