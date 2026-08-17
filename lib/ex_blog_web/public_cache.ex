defmodule ExBlogWeb.PublicCache do
  @moduledoc """
  Browser-cache headers for public pages.

  The ETag identifies a rendered response, so it has to cover *everything* that
  shapes it: the content commit, the page variant, the compiled code that
  renders it, and the runtime data it embeds. Leaving the code out means a
  deploy that only touches templates or translations keeps answering
  `304 Not Modified` until an article changes, and visitors keep seeing the
  previous page. The same applies to the daily ecosystem refresh, which changes
  the home page without touching either the commit or the code.
  """

  import Plug.Conn

  alias ExBlog.Content.Index
  alias ExBlog.Ecosystem

  # Modules whose compiled output ends up in a cached public response. Add any
  # new module that renders one, otherwise its changes stay invisible behind the
  # browser cache.
  @render_modules [
    __MODULE__,
    ExBlogWeb.Layouts,
    ExBlogWeb.CoreComponents,
    ExBlogWeb.Showcase,
    ExBlogWeb.BlogController,
    ExBlogWeb.BlogHTML,
    ExBlogWeb.FeedController,
    ExBlogWeb.LegalHTML,
    ExBlogWeb.SitemapController,
    ExBlogWeb.Gettext
  ]

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

  @doc "Returns the modules the ETag tracks, so a test can assert coverage."
  @spec render_modules() :: [module()]
  def render_modules, do: @render_modules

  defp etag(variant) do
    source = [
      Index.commit_hash() || "uncommitted",
      variant,
      render_version(),
      Ecosystem.fingerprint()
    ]

    digest = :crypto.hash(:sha256, Enum.join(source, ":")) |> Base.url_encode64(padding: false)

    ~s("#{digest}")
  end

  # The BEAM md5 of each rendering module. It changes on recompilation, so it
  # covers both a production deploy and a development code reload.
  defp render_version do
    @render_modules
    |> Enum.map(&module_md5/1)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  defp module_md5(module) do
    if Code.ensure_loaded?(module), do: module.module_info(:md5), else: <<>>
  end
end
