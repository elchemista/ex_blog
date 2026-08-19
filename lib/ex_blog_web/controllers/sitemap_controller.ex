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
  alias ExBlog.Content.Article
  alias ExBlog.Content.TranslationGroups
  alias ExBlogWeb.Canonical
  alias ExBlogWeb.PublicCache

  @legal_paths ["cookies-policy", "privacy-policy"]

  def show(conn, _params) do
    articles = indexed_articles()

    entries =
      public_pages()
      |> Kernel.++(article_entries(articles))
      |> Enum.map_join("\n", &url_entry/1)

    body =
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
              xmlns:xhtml="http://www.w3.org/1999/xhtml">
      #{entries}
      </urlset>
      """

    PublicCache.render(conn, "sitemap", fn cached_conn ->
      cached_conn
      |> put_resp_content_type("application/xml")
      |> send_resp(:ok, body)
    end)
  end

  # One entry per page, never one per URL that happens to render it. `/` and
  # `/<default language>` are the same page, so only the canonical one is listed:
  # advertising both told crawlers to index two copies of the home page while the
  # `canonical` tag told them to index one, and the two documents disagreeing is
  # worse than either choice alone.
  defp public_pages do
    languages = Config.get().supported_languages
    index_alternates = Canonical.index_alternates()

    index_entries =
      Enum.map(languages, fn language ->
        %{url: Canonical.index_url(language), lastmod: nil, alternates: index_alternates}
      end)

    legal_entries =
      Enum.flat_map(@legal_paths, fn path ->
        alternates = Canonical.localized_alternates(&"/#{&1}/#{path}")

        Enum.map(languages, fn language ->
          %{url: absolute("/#{language}/#{path}"), lastmod: nil, alternates: alternates}
        end)
      end)

    index_entries ++ legal_entries
  end

  defp indexed_articles do
    Content.list(lang: :all, status: :all)
    |> Enum.filter(fn article -> article.lang in Config.get().supported_languages end)
  end

  defp article_entries(articles) do
    published = Enum.filter(articles, &Article.published?/1)

    translation_groups =
      articles
      |> TranslationGroups.groups()
      |> Enum.map(&Enum.filter(&1, fn article -> article in published end))
      |> Enum.reject(&(&1 == []))
      |> Enum.reduce(%{}, fn group, groups ->
        Enum.reduce(group, groups, &Map.put(&2, &1.path, group))
      end)

    Enum.map(published, fn article ->
      alternates =
        translation_groups
        |> Map.fetch!(article.path)
        |> article_alternates()

      %{
        url: article_url(article),
        lastmod: article.updated || article.date,
        alternates: alternates
      }
    end)
  end

  defp article_alternates(articles) do
    language_order =
      Config.get().supported_languages
      |> Enum.with_index()
      |> Map.new()

    alternates =
      articles
      |> Enum.sort_by(fn article ->
        {Map.get(language_order, article.lang, map_size(language_order)), article.lang,
         article.slug}
      end)
      |> Enum.map(fn article -> %{hreflang: article.lang, url: article_url(article)} end)

    default = default_alternate(alternates)
    [%{hreflang: "x-default", url: default.url} | alternates]
  end

  defp default_alternate(alternates) do
    default_language = Config.get().default_language
    Enum.find(alternates, List.first(alternates), &(&1.hreflang == default_language))
  end

  defp article_url(%Article{} = article), do: absolute("/#{article.lang}/#{article.slug}")

  defp url_entry(%{url: url, lastmod: lastmod, alternates: alternates}) do
    lastmod_element =
      case date_string(lastmod) do
        nil -> ""
        date -> "\n    <lastmod>#{xml(date)}</lastmod>"
      end

    alternate_elements =
      Enum.map_join(alternates, "", fn alternate ->
        """

            <xhtml:link rel="alternate" hreflang="#{xml(alternate.hreflang)}" href="#{xml(alternate.url)}" />\
        """
      end)

    """
      <url>
        <loc>#{xml(url)}</loc>#{lastmod_element}#{alternate_elements}
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
