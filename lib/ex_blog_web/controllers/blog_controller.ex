defmodule ExBlogWeb.BlogController do
  use ExBlogWeb, :controller

  alias ExBlog.Config
  alias ExBlog.Content
  alias ExBlog.Content.Article
  alias ExBlog.Ecosystem
  alias ExBlogWeb.Canonical
  alias ExBlogWeb.Layouts
  alias ExBlogWeb.PublicCache
  alias ExBlogWeb.Showcase

  def home(conn, _params) do
    language = Config.get().default_language

    # `/` carries no language segment, so `ExBlogWeb.Plugs.Locale` would fall back
    # to whatever the visitor's session remembers. That is how a page could end up
    # declaring `lang="en"` while rendering Italian strings. One URL has to mean
    # one language, so the default is pinned here.
    _previous_locale = Gettext.put_locale(ExBlogWeb.Gettext, language)

    render_index(conn, language, Canonical.index_path(language), nil)
  end

  def index(conn, %{"lang" => language}) do
    if supported_language?(language) do
      render_index(conn, language, Canonical.index_path(language), nil)
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
        og_image_alt: article.cover_alt || article.title,
        alternates: article_alternates(article, translations),
        keywords: article_keywords(article),
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
      # An ETS read of the last daily refresh; nil until the first one lands.
      ecosystem: Ecosystem.snapshot(),
      current_language: language,
      supported_languages: Config.get().supported_languages,
      page_language: language,
      page_title: title,
      meta_description: description,
      canonical_url: absolute_url(path),
      og_type: "website",
      # No og_image: the layout falls back to the bundled preview and only then can
      # it also declare that image's dimensions.
      og_image_alt: gettext("Spectre — an OTP-native AI agent runtime for Elixir"),
      # Tag and category listings are filtered views of articles that are already
      # indexed on their own URLs, and `?lang=` makes a second near-duplicate of
      # each one. They stay crawlable so their outbound links still count, but they
      # must not compete with the articles themselves.
      robots: if(filter, do: "noindex,follow", else: "index,follow,max-image-preview:large"),
      alternates: if(filter, do: [], else: Canonical.index_alternates()),
      keywords: if(filter, do: nil, else: home_keywords()),
      json_ld: index_json_ld(path, description, language, filter, articles)
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

  # The front page is also the product page: the Spectre showcase and the article
  # list share one URL. Its title has to lead with the project name and the words
  # people type to look for it. The previous "Archive · EN" said nothing about
  # Spectre, Elixir, or agents, which are the only reasons anyone searches for
  # this site.
  defp index_metadata(_language, nil) do
    {
      gettext("Spectre — Enterprise AI Agents with Elixir, OTP and GAM"),
      Layouts.default_description()
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

  defp article_alternates(%Article{} = article, translations) do
    alternates =
      [article | translations]
      |> Enum.uniq_by(& &1.lang)
      |> Enum.map(&%{hreflang: &1.lang, url: absolute_url("/#{&1.lang}/#{&1.slug}")})

    default_language = Config.get().default_language

    case Enum.find(alternates, &(&1.hreflang == default_language)) do
      nil -> alternates
      default -> alternates ++ [%{hreflang: "x-default", url: default.url}]
    end
  end

  # Google has ignored `<meta name="keywords">` since 2009; Bing and Yandex still
  # read it. It is emitted because it costs one line, never as a substitute for
  # having the same words in the title, the description, and the page copy.
  defp home_keywords do
    Enum.join(
      [
        "Spectre",
        "Spectre agent",
        "Spectre AI",
        "Spectre Elixir",
        "Elixir AI agent",
        "secure AI agent",
        "enterprise AI agent",
        "governed AI agent",
        "OTP agent runtime",
        "AI agent framework Elixir"
      ],
      ", "
    )
  end

  defp article_keywords(%Article{tags: [], category: nil}), do: nil

  defp article_keywords(%Article{} = article) do
    [article.category | article.tags]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

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
    url = absolute_url(path)

    posting =
      %{
        "@type" => "BlogPosting",
        "@id" => url <> "#article",
        "headline" => article.title,
        "description" => article.seo_description || article.excerpt,
        "datePublished" => date_string(article.date),
        "dateModified" => date_string(article.updated || article.date),
        "inLanguage" => article.lang,
        "url" => url,
        "mainEntityOfPage" => %{"@type" => "WebPage", "@id" => url},
        "image" => cover_url(article.cover) || Layouts.default_og_image(),
        "keywords" => article_keywords(article),
        "articleSection" => article.category,
        "wordCount" => ExBlogWeb.BlogHTML.word_count(article.body),
        # Ties every post back to the one Spectre entity, so the posts reinforce
        # the project's identity instead of reading as unrelated pages.
        "about" => %{"@id" => software_id()},
        "isPartOf" => %{"@id" => website_id()},
        "author" => %{"@id" => organization_id()},
        "publisher" => %{"@id" => organization_id()}
      }
      |> reject_nil_values()

    %{"@context" => "https://schema.org", "@graph" => [organization_node(), posting]}
  end

  # A single entity graph naming the project, its language, its version, and the
  # places it is published from. This is what a search engine reads to decide that
  # "Spectre" is a specific piece of Elixir software and that this domain is its
  # home, which is the whole game for the "spectre agent" / "spectre ai" /
  # "spectre elixir" queries.
  defp index_json_ld(path, description, language, nil, articles) do
    %{
      "@context" => "https://schema.org",
      "@graph" => [
        organization_node(),
        website_node(description, language),
        software_node(description),
        blog_node(path, description, language, articles)
      ]
    }
  end

  defp index_json_ld(path, description, language, _filter, articles) do
    %{
      "@context" => "https://schema.org",
      "@graph" => [organization_node(), blog_node(path, description, language, articles)]
    }
  end

  defp site_url, do: Config.canonical_url()
  defp organization_id, do: site_url() <> "/#organization"
  defp website_id, do: site_url() <> "/#website"
  defp software_id, do: site_url() <> "/#spectre"

  # Spelled exactly like the canonical tag and og:url. A node whose `url` differs
  # from the canonical by a trailing slash is a second address for the same thing,
  # which is the opposite of what this graph is for.
  defp home_url, do: absolute_url("/")

  defp organization_node do
    %{
      "@type" => "Organization",
      "@id" => organization_id(),
      "name" => "elchemista",
      "url" => "https://elchemista.com",
      "logo" => %{"@type" => "ImageObject", "url" => Layouts.default_og_image()},
      "sameAs" => ["https://github.com/elchemista"]
    }
  end

  defp website_node(description, language) do
    %{
      "@type" => "WebSite",
      "@id" => website_id(),
      "name" => Layouts.site_name(),
      "url" => home_url(),
      "description" => description,
      "inLanguage" => language,
      "publisher" => %{"@id" => organization_id()},
      "about" => %{"@id" => software_id()}
    }
  end

  defp software_node(description) do
    %{
      "@type" => ["SoftwareApplication", "SoftwareSourceCode"],
      "@id" => software_id(),
      "name" => Layouts.site_name(),
      "description" => description,
      "url" => home_url(),
      "applicationCategory" => "DeveloperApplication",
      "operatingSystem" => "Erlang/OTP",
      "runtimePlatform" => "Erlang/OTP",
      "programmingLanguage" => "Elixir",
      "softwareVersion" => Showcase.spectre_version(),
      "codeRepository" => Showcase.spectre_repo_url(),
      # deps/spectre/mix.exs declares Apache-2.0 for the core package.
      "license" => "https://www.apache.org/licenses/LICENSE-2.0",
      "author" => %{"@id" => organization_id()},
      "maintainer" => %{"@id" => organization_id()},
      "isAccessibleForFree" => true,
      "offers" => %{"@type" => "Offer", "price" => "0", "priceCurrency" => "EUR"},
      "sameAs" => [
        Showcase.spectre_repo_url(),
        "https://hex.pm/packages/spectre",
        Showcase.spectre_hexdocs_url()
      ]
    }
  end

  defp blog_node(path, description, language, articles) do
    %{
      "@type" => "Blog",
      "@id" => absolute_url(path) <> "#blog",
      "name" => Layouts.site_name(),
      "url" => absolute_url(path),
      "description" => description,
      "inLanguage" => language,
      "publisher" => %{"@id" => organization_id()},
      "blogPost" => blog_post_nodes(articles)
    }
    |> reject_nil_values()
  end

  # An empty `blogPost` array claims the blog was inspected and found to have no
  # posts. Leaving the property out claims nothing.
  defp blog_post_nodes([]), do: nil
  defp blog_post_nodes(articles), do: Enum.map(articles, &blog_post_node/1)

  defp blog_post_node(%Article{} = article) do
    %{
      "@type" => "BlogPosting",
      "@id" => absolute_url("/#{article.lang}/#{article.slug}") <> "#article",
      "headline" => article.title,
      "url" => absolute_url("/#{article.lang}/#{article.slug}"),
      "datePublished" => date_string(article.date),
      "dateModified" => date_string(article.updated || article.date),
      "inLanguage" => article.lang
    }
    |> reject_nil_values()
  end

  defp reject_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp date_string(%Date{} = date), do: Date.to_iso8601(date)
  defp date_string(_date), do: nil
end
