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

  defp public_pages do
    index_alternates = localized_alternates(fn language -> "/#{language}" end)

    index_entries =
      [
        %{
          url: absolute("/"),
          lastmod: nil,
          alternates: [%{language: "x-default", url: absolute("/")} | index_alternates]
        }
      ] ++ localized_entries(index_alternates, absolute("/"))

    legal_entries =
      Enum.flat_map(@legal_paths, fn path ->
        localized_alternates(fn language -> "/#{language}/#{path}" end)
        |> localized_entries()
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

  defp localized_alternates(path_builder) do
    Enum.map(Config.get().supported_languages, fn language ->
      %{language: language, url: absolute(path_builder.(language))}
    end)
  end

  defp localized_entries(alternates, x_default_url \\ nil) do
    default_url = x_default_url || default_alternate(alternates).url
    complete_alternates = [%{language: "x-default", url: default_url} | alternates]

    Enum.map(alternates, fn alternate ->
      %{url: alternate.url, lastmod: nil, alternates: complete_alternates}
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
      |> Enum.map(fn article -> %{language: article.lang, url: article_url(article)} end)

    default = default_alternate(alternates)
    [%{language: "x-default", url: default.url} | alternates]
  end

  defp default_alternate(alternates) do
    default_language = Config.get().default_language
    Enum.find(alternates, List.first(alternates), &(&1.language == default_language))
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

            <xhtml:link rel="alternate" hreflang="#{xml(alternate.language)}" href="#{xml(alternate.url)}" />\
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
