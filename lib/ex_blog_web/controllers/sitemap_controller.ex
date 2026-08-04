defmodule ExBlogWeb.SitemapController do
  @moduledoc """
  Builds the XML sitemap from the current public content index.

  Unlike `robots.txt`, the sitemap cannot be a static asset: published articles
  change whenever the content repository is synchronized. Keeping generation in
  this dedicated controller makes that distinction explicit.
  """

  use ExBlogWeb, :controller

  alias ExBlog.Config
  alias ExBlog.Content
  alias ExBlogWeb.PublicCache

  def show(conn, _params) do
    entries =
      public_indexes()
      |> Kernel.++(published_articles())
      |> Enum.map_join("\n", &url_entry/1)

    body =
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{entries}
      </urlset>
      """

    PublicCache.render(conn, "sitemap", fn cached_conn ->
      cached_conn
      |> put_resp_content_type("application/xml")
      |> send_resp(:ok, body)
    end)
  end

  defp public_indexes do
    [%{url: absolute("/"), lastmod: nil}] ++
      Enum.map(Config.get().supported_languages, fn language ->
        %{url: absolute("/#{language}"), lastmod: nil}
      end)
  end

  defp published_articles do
    Content.list(lang: :all)
    |> Enum.map(fn article ->
      %{
        url: absolute("/#{article.lang}/#{article.slug}"),
        lastmod: article.updated || article.date
      }
    end)
  end

  defp url_entry(%{url: url, lastmod: lastmod}) do
    lastmod_element =
      case date_string(lastmod) do
        nil -> ""
        date -> "\n    <lastmod>#{xml(date)}</lastmod>"
      end

    """
      <url>
        <loc>#{xml(url)}</loc>#{lastmod_element}
      </url>
    """
  end

  defp absolute(path), do: Config.canonical_url() <> path

  defp xml(nil), do: ""

  defp xml(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp date_string(%Date{} = date), do: Date.to_iso8601(date)
  defp date_string(_date), do: nil
end
