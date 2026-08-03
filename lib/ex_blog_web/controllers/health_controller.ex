defmodule ExBlogWeb.HealthController do
  use ExBlogWeb, :controller

  alias ExBlog.Content.Index

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(%{status: "ok", commit: Index.commit_hash()})
  end
end
