defmodule ExBlogWeb.HealthController do
  use ExBlogWeb, :controller

  alias ExBlog.Content.Sync

  def show(conn, _params) do
    sync = Sync.status()

    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(%{
      status: "ok",
      commit: sync.commit,
      content_sync: %{
        status: Atom.to_string(sync.status),
        last_finished_at: sync.last_finished_at,
        duration_ms: sync.duration_ms,
        error: sync.error
      }
    })
  end
end
