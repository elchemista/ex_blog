defmodule ExBlogWeb.BlogController do
  use ExBlogWeb, :controller

  alias ExBlog.Config
  alias ExBlog.Content
  alias ExBlog.Content.Article
  alias ExBlogWeb.Layouts
  alias ExBlogWeb.PublicCache

  def home(conn, _params) do
    language = Config.get().default_language
    render_index(conn, language, ~p"/", nil)
  end

  def index(conn, %{"lang" => language}) do
    if supported_language?(language) do
      render_index(conn, language, ~p"/#{language}", nil)
    else
      not_found(conn, language)
    end
  end

  def show(conn, %{"lang" => language, "slug" => slug}) do
    with true <- supported_language?(language),
         {:ok, article} <- Content.get(language, slug) do
      path = ~p"/#{language}/#{slug}"
      translations = Content.translations(article) |> Enum.filter(&Article.published?/1)
      related = related_articles(article)
      description = article.seo_description || article.excerpt || article.title

      assigns = [
        article: article,
        translations: translations,
        related: related,
        current_language: language,
        supported_languages: Config.get().supported_languages,
        page_language: language,
        page_title: article.seo_title || article.title,
        meta_description: description,
        canonical_url: absolute_url(path),
        og_type: "article",
        og_image: cover_url(article.cover),
        og_image_alt: article.cover_alt,
        json_ld: article_json_ld(article, path)
      ]

      PublicCache.render(conn, "article:#{language}:#{slug}", &render(&1, :show, assigns))
    else
      _not_found -> not_found(conn, language)
    end
  end

  def tag(conn, %{"tag" => tag} = params) do
    language = requested_language(params)

    if supported_language?(language) do
      articles = Content.by_tag(tag, lang: language)
      path = ~p"/tag/#{tag}?lang=#{language}"
      filter = %{kind: :tag, value: tag}
      render_index(conn, language, path, filter, articles)
    else
      not_found(conn, language)
    end
  end

  def category(conn, %{"category" => category} = params) do
    language = requested_language(params)

    if supported_language?(language) do
      articles = Content.by_category(category, lang: language)
      path = ~p"/category/#{category}?lang=#{language}"
      filter = %{kind: :category, value: category}
      render_index(conn, language, path, filter, articles)
    else
      not_found(conn, language)
    end
  end

  defp render_index(conn, language, path, filter, articles \\ nil) do
    articles = articles || Content.list(lang: language)
    {featured, remaining} = split_featured(articles)

    {title, description} = index_metadata(language, filter)

    assigns = [
      articles: articles,
      featured: featured,
      remaining: remaining,
      filter: filter,
      current_language: language,
      supported_languages: Config.get().supported_languages,
      page_language: language,
      page_title: title,
      meta_description: description,
      canonical_url: absolute_url(path),
      og_type: "website",
      json_ld: website_json_ld(path, description)
    ]

    variant = "index:#{language}:#{filter_key(filter)}"
    PublicCache.render(conn, variant, &render(&1, :index, assigns))
  end

  defp not_found(conn, language) do
    conn
    |> put_status(:not_found)
    |> put_resp_header("cache-control", "no-store")
    |> render(:not_found,
      current_language: language_if_supported(language),
      supported_languages: Config.get().supported_languages,
      page_title: gettext("Page not found"),
      meta_description: gettext("The requested page does not exist."),
      robots: "noindex,follow",
      canonical_url: Config.canonical_url()
    )
  end

  defp related_articles(%Article{category: nil}), do: []

  defp related_articles(article) do
    article.category
    |> Content.by_category(lang: article.lang)
    |> Enum.reject(&(&1.slug == article.slug))
    |> Enum.take(3)
  end

  defp split_featured([]), do: {nil, []}
  defp split_featured([article | remaining]), do: {article, remaining}

  defp index_metadata(language, nil) do
    language = String.upcase(language)

    {
      gettext("Archive · %{language}", language: language),
      gettext("Development notes, technical write-ups and stories published in %{language}.",
        language: language
      )
    }
  end

  defp index_metadata(_language, %{kind: :tag, value: value}) do
    {gettext("Tag: %{tag}", tag: value), gettext("Every article tagged %{tag}.", tag: value)}
  end

  defp index_metadata(_language, %{kind: :category, value: value}) do
    {gettext("Category: %{category}", category: value),
     gettext("Every article in the %{category} category.", category: value)}
  end

  defp filter_key(nil), do: "all"
  defp filter_key(%{kind: kind, value: value}), do: "#{kind}:#{value}"

  defp requested_language(params),
    do: Map.get(params, "lang", Config.get().default_language)

  defp supported_language?(language),
    do: language in Config.get().supported_languages

  defp language_if_supported(language) do
    if supported_language?(language), do: language, else: Config.get().default_language
  end

  defp absolute_url(path), do: Config.canonical_url() <> path

  defp cover_url(nil), do: nil
  defp cover_url("/" <> _rest = path), do: absolute_url(path)

  defp cover_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) -> url
      _other -> nil
    end
  end

  defp article_json_ld(article, path) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Article",
      "headline" => article.title,
      "description" => article.seo_description || article.excerpt,
      "datePublished" => date_string(article.date),
      "dateModified" => date_string(article.updated || article.date),
      "inLanguage" => article.lang,
      "mainEntityOfPage" => absolute_url(path),
      "image" => cover_url(article.cover),
      "author" => %{"@type" => "Organization", "name" => Layouts.site_name()},
      "publisher" => %{"@type" => "Organization", "name" => Layouts.site_name()}
    }
    |> reject_nil_values()
  end

  defp website_json_ld(path, description) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Blog",
      "name" => Layouts.site_name(),
      "url" => absolute_url(path),
      "description" => description
    }
  end

  defp reject_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp date_string(%Date{} = date), do: Date.to_iso8601(date)
  defp date_string(_date), do: nil
end
