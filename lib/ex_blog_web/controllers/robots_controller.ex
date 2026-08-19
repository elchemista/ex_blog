defmodule ExBlogWeb.RobotsController do
  @moduledoc """
  Serves `robots.txt` from the running deployment's own host.

  This used to be a static asset in `priv/static`, which meant the `Sitemap:`
  line carried a hard-coded domain. When the deployment moved the file kept
  advertising the old one, so crawlers were pointed at a host that no longer
  serves this site and the sitemap was never fetched. The canonical URL is
  runtime configuration, so the document that publishes it has to be rendered at
  runtime too.

  `/tag` and `/category` are deliberately *not* disallowed here: they answer with
  `noindex,follow` instead, which keeps them crawlable so the links to the
  articles they list still pass through.
  """

  use ExBlogWeb, :controller

  alias ExBlog.Config
  alias ExBlogWeb.PublicCache

  @disallowed ["/admin", "/mcp", "/oauth", "/health", "/.well-known/oauth-protected-resource"]

  def show(conn, _params) do
    body = """
    User-agent: *
    Allow: /
    #{Enum.map_join(@disallowed, "\n", &"Disallow: #{&1}")}

    Sitemap: #{Config.canonical_url()}/sitemap.xml
    """

    PublicCache.render(conn, "robots", fn cached_conn ->
      cached_conn
      |> put_resp_content_type("text/plain")
      |> send_resp(:ok, body)
    end)
  end
end
