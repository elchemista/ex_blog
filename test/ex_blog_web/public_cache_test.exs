defmodule ExBlogWeb.PublicCacheTest do
  use ExBlogWeb.ConnCase, async: true

  alias ExBlog.Config
  alias ExBlog.Content.Index
  alias ExBlogWeb.PublicCache

  describe "public page etag" do
    test "covers every module that renders a cached response" do
      # A page whose module is missing here keeps answering 304 Not Modified
      # after a deploy that only changed templates or translations.
      tracked = PublicCache.render_modules()

      for module <- [
            ExBlogWeb.PublicCache,
            ExBlogWeb.Layouts,
            ExBlogWeb.CoreComponents,
            ExBlogWeb.Showcase,
            ExBlogWeb.BlogController,
            ExBlogWeb.BlogHTML,
            ExBlogWeb.FeedController,
            ExBlogWeb.LegalHTML,
            ExBlogWeb.SitemapController,
            ExBlogWeb.Gettext
          ] do
        assert module in tracked,
               "#{inspect(module)} renders cached HTML but is not part of the ETag"
      end
    end

    test "is not derived from the content commit and variant alone", %{conn: conn} do
      # The original bug: the ETag ignored the compiled code, so changing a
      # template never invalidated a browser cache until an article changed.
      language = Config.get().default_language
      commit = Index.commit_hash() || "uncommitted"

      code_independent =
        :sha256
        |> :crypto.hash("#{commit}:index:#{language}:all")
        |> Base.url_encode64(padding: false)

      assert etag_for(conn, "/") != ~s("#{code_independent}")
    end

    test "differs per language", %{conn: conn} do
      assert etag_for(conn, "/it") != etag_for(conn, "/en")
    end

    test "still answers 304 while the build is unchanged", %{conn: conn} do
      etag = etag_for(conn, "/")

      response =
        conn
        |> put_req_header("if-none-match", etag)
        |> get("/")

      assert response.status == 304
    end
  end

  defp etag_for(conn, path) do
    [etag] = conn |> get(path) |> get_resp_header("etag")
    etag
  end
end
