defmodule ExBlogWeb.PublicCache do
  @moduledoc false

  import Plug.Conn

  alias ExBlog.Content.Index

  @spec render(Plug.Conn.t(), String.t(), (Plug.Conn.t() -> Plug.Conn.t())) :: Plug.Conn.t()
  def render(conn, variant, renderer) when is_binary(variant) and is_function(renderer, 1) do
    etag = etag(variant)

    conn =
      conn
      |> put_resp_header("etag", etag)
      |> put_resp_header("cache-control", "public, max-age=60, stale-while-revalidate=300")

    if etag in get_req_header(conn, "if-none-match") do
      send_resp(conn, :not_modified, "")
    else
      renderer.(conn)
    end
  end

  defp etag(variant) do
    source = "#{Index.commit_hash() || "uncommitted"}:#{variant}"
    digest = :crypto.hash(:sha256, source) |> Base.url_encode64(padding: false)
    ~s("#{digest}")
  end
end
