defmodule ExBlogWeb.FeedController do
  use ExBlogWeb, :controller

  alias ExBlog.Config
  alias ExBlog.Content
  alias ExBlogWeb.PublicCache

  def sitemap(conn, _params) do
    entries =
      Content.list(lang: :all)
      |> Enum.map_join("\n", fn article ->
        """
          <url>
            <loc>#{xml(absolute("/#{article.lang}/#{article.slug}"))}</loc>
            <lastmod>#{xml(date_string(article.updated || article.date))}</lastmod>
          </url>
        """
      end)

    body =
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{entries}
      </urlset>
      """

    PublicCache.render(conn, "sitemap", &xml_response(&1, body, "application/xml"))
  end

  def robots(conn, _params) do
    body =
      """
      User-agent: *
      Allow: /
      Disallow: /admin
      Disallow: /mcp

      Sitemap: #{absolute("/sitemap.xml")}
      """

    PublicCache.render(conn, "robots", fn cached_conn ->
      cached_conn
      |> put_resp_content_type("text/plain")
      |> send_resp(:ok, body)
    end)
  end

  def rss(conn, _params) do
    language = Config.get().default_language

    items =
      Content.list(lang: language)
      |> Enum.take(30)
      |> Enum.map_join("\n", fn article ->
        link = absolute("/#{article.lang}/#{article.slug}")

        """
          <item>
            <title>#{xml(article.title)}</title>
            <link>#{xml(link)}</link>
            <guid isPermaLink="true">#{xml(link)}</guid>
            <description>#{xml(article.seo_description || article.excerpt)}</description>
            <pubDate>#{xml(rfc822(article.date))}</pubDate>
          </item>
        """
      end)

    body =
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>ExBlog</title>
          <link>#{xml(absolute("/"))}</link>
          <description>Idee, appunti e storie pubblicate con cura.</description>
          <language>#{xml(language)}</language>
          #{items}
        </channel>
      </rss>
      """

    PublicCache.render(conn, "rss:#{language}", &xml_response(&1, body, "application/rss+xml"))
  end

  def atom(conn, _params) do
    language = Config.get().default_language
    articles = Content.list(lang: language) |> Enum.take(30)
    updated = articles |> List.first() |> then(&date_from_article/1)

    entries =
      Enum.map_join(articles, "\n", fn article ->
        link = absolute("/#{article.lang}/#{article.slug}")

        """
          <entry>
            <title>#{xml(article.title)}</title>
            <id>#{xml(link)}</id>
            <link href="#{xml(link)}" />
            <updated>#{xml(iso8601(article.updated || article.date))}</updated>
            <summary>#{xml(article.seo_description || article.excerpt)}</summary>
          </entry>
        """
      end)

    body =
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom" xml:lang="#{xml(language)}">
        <title>ExBlog</title>
        <id>#{xml(absolute("/"))}</id>
        <link href="#{xml(absolute("/atom.xml"))}" rel="self" />
        <link href="#{xml(absolute("/"))}" />
        <updated>#{xml(iso8601(updated))}</updated>
        #{entries}
      </feed>
      """

    PublicCache.render(conn, "atom:#{language}", &xml_response(&1, body, "application/atom+xml"))
  end

  defp xml_response(conn, body, content_type) do
    conn
    |> put_resp_content_type(content_type)
    |> send_resp(:ok, body)
  end

  defp absolute(path), do: Config.canonical_url() <> path

  defp xml(nil), do: ""

  defp xml(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp date_from_article(nil), do: Date.utc_today()
  defp date_from_article(article), do: article.updated || article.date || Date.utc_today()

  defp date_string(%Date{} = date), do: Date.to_iso8601(date)
  defp date_string(_date), do: nil

  defp iso8601(%Date{} = date), do: Date.to_iso8601(date) <> "T00:00:00Z"
  defp iso8601(_date), do: Date.utc_today() |> iso8601()

  defp rfc822(%Date{} = date), do: Calendar.strftime(date, "%a, %d %b %Y 00:00:00 GMT")
  defp rfc822(_date), do: Date.utc_today() |> rfc822()
end
