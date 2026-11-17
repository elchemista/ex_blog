defmodule ExBlogWeb.BlogControllerTest do
  use ExBlogWeb.ConnCase, async: false

  alias ExBlog.Config
  alias ExBlog.Content.Index

  setup do
    root = temporary_directory()
    italian = Path.join([root, "content", "it"])
    english = Path.join([root, "content", "en"])
    french = Path.join([root, "content", "fr"])
    File.mkdir_p!(italian)
    File.mkdir_p!(english)
    File.mkdir_p!(french)

    previous_config = Config.get()

    Config.install(struct!(previous_config, supported_languages: ["it", "en", "fr"]))

    File.write!(
      Path.join(italian, "2026-08-03-primo-articolo.md"),
      article("Primo articolo", "primo-articolo", "it", "published",
        category: "Tecnologia",
        tags: ["elixir", "phoenix"],
        cover: "/images/articles/primo-articolo.jpg",
        cover_alt: "Diagramma del primo articolo",
        body: "## Un sottotitolo\n\nContenuto **importante**.\n\n<script>alert('no')</script>"
      )
    )

    File.write!(
      Path.join(italian, "2026-08-02-bozza-segreta.md"),
      article("Bozza segreta", "bozza-segreta", "it", "draft")
    )

    File.write!(
      Path.join(english, "2026-08-03-first-article.md"),
      article("First article", "first-article", "en", "published",
        translation_of: "content/it/2026-08-03-primo-articolo.md"
      )
    )

    File.write!(
      Path.join(french, "2026-08-03-premier-article.md"),
      article("Premier article", "premier-article", "fr", "published",
        translation_of: "content/it/2026-08-03-primo-articolo.md"
      )
    )

    File.write!(
      Path.join(italian, "2026-08-03-agente-news.md"),
      article("Agente news", "agente-news", "it", "published",
        tags: ["elixir", "spectre", "lens", "kinetic"]
      )
    )

    File.write!(
      Path.join(english, "2026-08-03-news-agent.md"),
      article("News agent", "news-agent", "en", "published",
        tags: ["elixir", "spectre", "lens", "kinetic"]
      )
    )

    File.write!(
      Path.join(italian, "2026-08-03-testare-agenti.md"),
      article("Testare agenti", "testare-agenti", "it", "published",
        tags: ["elixir", "spectre", "exunit", "policy"]
      )
    )

    File.write!(
      Path.join(english, "2026-08-03-testing-agents.md"),
      article("Testing agents", "testing-agents", "en", "published",
        tags: ["elixir", "spectre", "exunit", "policy"]
      )
    )

    start_supervised!({Index, root: root, content_root: "content"})

    on_exit(fn ->
      Config.install(previous_config)
      File.rm_rf!(root)
    end)

    :ok
  end

  test "renders the public index with published articles only", %{conn: conn} do
    document = conn |> get("/") |> html_document(200)

    assert one?(document, "#blog-index")

    assert document |> LazyHTML.query("#homepage-title") |> LazyHTML.text() |> String.trim() ==
             "L’unico modo giusto di costruire agenti AI per le aziende."

    subtitle = document |> LazyHTML.query("#homepage-subtitle") |> LazyHTML.text()
    assert subtitle =~ "permessi"
    assert subtitle =~ "GAM"

    assert one?(document, "#spectre-principles")
    assert one?(document, "#governed-act-model-feature")
    assert one?(document, ~s(#governed-act-model-cta[href="/it/governed-act-model"]))
    assert one?(document, ~s(#manifesto-nav-link[href="/it/governed-act-model"]))
    assert one?(document, "#article-card-it-primo-articolo")
    refute one?(document, "#article-card-it-bozza-segreta")
    assert LazyHTML.attribute(LazyHTML.query(document, "html"), "lang") == ["it"]
  end

  test "renders the Spectre positioning in English", %{conn: conn} do
    document = conn |> get("/en") |> html_document(200)

    assert document |> LazyHTML.query("#homepage-title") |> LazyHTML.text() |> String.trim() ==
             "The only right way to build enterprise AI agents."

    subtitle = document |> LazyHTML.query("#homepage-subtitle") |> LazyHTML.text()
    assert subtitle =~ "permissions you grant"
    assert subtitle =~ "GAM"

    assert LazyHTML.text(LazyHTML.query(document, "#governed-act-model-feature-title")) =~
             "It does not grant itself power"

    assert one?(document, ~s(#governed-act-model-cta[href="/en/governed-act-model"]))
  end

  test "the index head names Spectre, Elixir, and AI agents", %{conn: conn} do
    document = conn |> get("/") |> html_document(200)
    base = ExBlog.Config.canonical_url()

    # The title used to read "Archivio · IT · Spectre", which contains none of the
    # words anyone searches for. It has to lead with the project and name what it is.
    title = document |> LazyHTML.query("title") |> LazyHTML.text()
    assert title =~ "Spectre"
    assert title =~ "Elixir"
    assert String.length(title) <= 60

    assert one?(document, ~s(meta[name="description"][content*="Spectre"]))
    assert one?(document, ~s(meta[name="description"][content*="AI"]))
    assert one?(document, ~s(meta[name="robots"][content="index,follow,max-image-preview:large"]))

    # `/` is the canonical home page; `/it` renders the same content and points here
    # rather than competing with it.
    assert one?(document, ~s(link[rel="canonical"][href="#{base}/"]))

    localized = build_conn() |> get("/it") |> html_document(200)
    assert one?(localized, ~s(link[rel="canonical"][href="#{base}/"]))

    english = build_conn() |> get("/en") |> html_document(200)
    assert one?(english, ~s(link[rel="canonical"][href="#{base}/en"]))

    # hreflang has to be in the document, not only in the sitemap, and must include
    # the page itself.
    assert one?(document, ~s(link[rel="alternate"][hreflang="it"][href="#{base}/"]))
    assert one?(document, ~s(link[rel="alternate"][hreflang="en"][href="#{base}/en"]))
    assert one?(document, ~s(link[rel="alternate"][hreflang="x-default"][href="#{base}/"]))

    assert one?(document, ~s(meta[property="og:image"][content="#{base}/images/og-default.png"]))
    assert one?(document, ~s(meta[property="og:locale"][content="it_IT"]))
    assert one?(document, ~s(meta[property="og:locale:alternate"][content="en_US"]))
  end

  test "the index publishes a Spectre entity graph", %{conn: conn} do
    document = conn |> get("/") |> html_document(200)

    graph =
      document
      |> LazyHTML.query(~s(script[type="application/ld+json"]))
      |> LazyHTML.text()
      |> Jason.decode!()
      |> Map.fetch!("@graph")

    types = Enum.map(graph, & &1["@type"])
    assert "Organization" in types
    assert "WebSite" in types
    assert "Blog" in types

    # The node a search engine reads to decide that "Spectre" is a specific piece of
    # Elixir software and that this domain is where it lives.
    software = Enum.find(graph, &(&1["@type"] == ["SoftwareApplication", "SoftwareSourceCode"]))

    assert software["name"] == "Spectre"
    assert software["programmingLanguage"] == "Elixir"
    assert software["codeRepository"] == "https://github.com/elchemista/spectre"
    assert "https://hex.pm/packages/spectre" in software["sameAs"]
  end

  test "an article links itself back to the Spectre entity", %{conn: conn} do
    document = conn |> get("/it/primo-articolo") |> html_document(200)
    base = ExBlog.Config.canonical_url()

    graph =
      document
      |> LazyHTML.query(~s(script[type="application/ld+json"]))
      |> LazyHTML.text()
      |> Jason.decode!()
      |> Map.fetch!("@graph")

    posting = Enum.find(graph, &(&1["@type"] == "BlogPosting"))

    assert posting["headline"] == "Primo articolo"
    assert posting["about"] == %{"@id" => "#{base}/#spectre"}
    assert posting["keywords"] == "Tecnologia, elixir, phoenix"
    assert posting["wordCount"] > 0

    assert one?(
             document,
             ~s(link[rel="alternate"][hreflang="en"][href="#{base}/en/first-article"])
           )
  end

  test "explains philosophy, capabilities, and governed evolution", %{conn: conn} do
    document = conn |> get("/en") |> html_document(200)

    assert one?(document, "#spectre-philosophy-proposal")
    assert one?(document, "#spectre-philosophy-routing")
    assert one?(document, "#spectre-philosophy-data")

    capabilities =
      document |> LazyHTML.query("#spectre-capabilities-explainer") |> LazyHTML.text()

    assert capabilities =~ "Server"
    assert capabilities =~ "GAM"

    assert LazyHTML.text(LazyHTML.query(document, "#spectre-evolution")) =~
             "approval"

    assert one?(document, "#spectre-evolution-step-4")
  end

  test "presents the 0.4 Stack, Agent, and Server example in architectural order", %{conn: conn} do
    document = conn |> get("/en") |> html_document(200)
    sample = document |> LazyHTML.query("#spectre-agent-server-example code") |> LazyHTML.text()

    assert {stack, _} = :binary.match(sample, "defmodule MyApp.AI do")
    assert {agent, _} = :binary.match(sample, "defmodule MyApp.SupportAgent do")
    assert {server, _} = :binary.match(sample, "defmodule MyApp.SupportServer do")
    assert stack < agent
    assert agent < server
    assert sample =~ "use Spectre.Stack"
    assert sample =~ "use Spectre.Server"
    refute sample =~ ~r/\bprotect\s*\(|\bpolicy\s+:/

    assert document
           |> LazyHTML.query(~s(a[href="https://hexdocs.pm/spectre/0.4.0"]))
           |> LazyHTML.text() =~ "0.4.0"
  end

  test "renders sanitized article HTML, metadata, tags, and language alternatives", %{conn: conn} do
    document = conn |> get("/it/primo-articolo") |> html_document(200)

    assert one?(document, "#article-it-primo-articolo")
    assert one?(document, "#article-body h2")
    refute one?(document, "#article-body script")
    assert one?(document, ~s(a[href="/tag/elixir?lang=it"]))
    assert one?(document, ~s(a[hreflang="en"][href="/en/first-article"]))
    assert one?(document, "#article-cover")

    assert one?(
             document,
             ~s(img#article-cover-image[src="/images/articles/primo-articolo.jpg"][alt="Diagramma del primo articolo"])
           )

    assert LazyHTML.attribute(LazyHTML.query(document, ~s(meta[property="og:type"])), "content") ==
             ["article"]

    assert one?(document, ~s(script[type="application/ld+json"]))
  end

  test "does not expose drafts and renders a clean 404", %{conn: conn} do
    document = conn |> get("/it/bozza-segreta") |> html_document(404)
    assert one?(document, "#not-found")
  end

  test "links unambiguous legacy translations that predate translation_of", %{conn: conn} do
    document = conn |> get("/it/agente-news") |> html_document(200)

    assert one?(document, ~s(link[rel="alternate"][hreflang="en"][href$="/en/news-agent"]))
    assert one?(document, ~s(a[hreflang="en"][href="/en/news-agent"]))
    refute one?(document, ~s(a[href="/en/testing-agents"]))
  end

  test "filters by tag and category", %{conn: conn} do
    tag_document = conn |> get("/tag/elixir?lang=it") |> html_document(200)
    assert one?(tag_document, "#active-filter")
    assert one?(tag_document, "#article-card-it-primo-articolo")

    category_document =
      build_conn()
      |> get("/category/Tecnologia?lang=it")
      |> html_document(200)

    assert one?(category_document, "#article-card-it-primo-articolo")
  end

  test "serves the dynamic sitemap, static robots, feeds, and conditional caching", %{conn: conn} do
    sitemap = get(conn, "/sitemap.xml")
    base = ExBlog.Config.canonical_url()
    body = response(sitemap, 200)

    assert body =~ ~s(xmlns:xhtml="http://www.w3.org/1999/xhtml")
    assert body =~ "<loc>#{base}/</loc>"
    assert body =~ "<loc>#{base}/en</loc>"
    assert body =~ "<loc>#{base}/fr</loc>"
    assert body =~ "<loc>#{base}/it/privacy-policy</loc>"
    assert body =~ "<loc>#{base}/fr/cookies-policy</loc>"
    assert body =~ "<loc>#{base}/it/governed-act-model</loc>"
    assert body =~ "<loc>#{base}/en/governed-act-model</loc>"
    refute body =~ "<loc>#{base}/fr/governed-act-model</loc>"
    refute body =~ "bozza-segreta"

    # `/` and `/<default language>` render the same page, so the sitemap advertises
    # only the canonical one. Listing both asked crawlers to index two copies of the
    # home page while the canonical tag named a single URL.
    refute body =~ "<loc>#{base}/it</loc>"

    index_entry = sitemap_entry(body, "#{base}/")
    assert index_entry =~ ~s(<xhtml:link rel="alternate" hreflang="it" href="#{base}/" />)
    assert index_entry =~ ~s(<xhtml:link rel="alternate" hreflang="en" href="#{base}/en" />)
    assert index_entry =~ ~s(<xhtml:link rel="alternate" hreflang="x-default" href="#{base}/" />)

    article_urls = %{
      "it" => "#{base}/it/primo-articolo",
      "en" => "#{base}/en/first-article",
      "fr" => "#{base}/fr/premier-article"
    }

    article_entries = Enum.map(article_urls, fn {_language, url} -> sitemap_entry(body, url) end)

    for entry <- article_entries, {language, url} <- article_urls do
      assert entry =~
               ~s(<xhtml:link rel="alternate" hreflang="#{language}" href="#{url}" />)
    end

    for entry <- article_entries do
      assert entry =~
               ~s(<xhtml:link rel="alternate" hreflang="x-default" href="#{article_urls["it"]}" />)
    end

    for {_language, url} <- article_urls do
      assert length(Regex.scan(~r/<loc>#{Regex.escape(url)}<\/loc>/, body)) == 1
    end

    legacy_pairs = [
      {"#{base}/it/agente-news", "#{base}/en/news-agent"},
      {"#{base}/it/testare-agenti", "#{base}/en/testing-agents"}
    ]

    for {italian_url, english_url} <- legacy_pairs do
      for entry <- [sitemap_entry(body, italian_url), sitemap_entry(body, english_url)] do
        assert entry =~ ~s(hreflang="it" href="#{italian_url}")
        assert entry =~ ~s(hreflang="en" href="#{english_url}")
      end
    end

    news_entry = sitemap_entry(body, "#{base}/it/agente-news")
    refute news_entry =~ "testing-agents"

    assert get_resp_header(sitemap, "content-type") == ["application/xml; charset=utf-8"]

    rss = get(build_conn(), "/feed.xml")
    assert response(rss, 200) =~ "<rss version=\"2.0\">"

    atom = get(build_conn(), "/atom.xml")
    assert response(atom, 200) =~ "http://www.w3.org/2005/Atom"

    robots = get(build_conn(), "/robots.txt")
    robots_body = response(robots, 200)
    assert robots_body =~ "Disallow: /admin"
    assert robots_body =~ "Disallow: /mcp"
    assert robots_body =~ "Disallow: /oauth"
    assert robots_body =~ "Disallow: /health"

    # This assertion used to name a hard-coded host that the deployment had already
    # moved away from, so crawlers were sent to a domain that no longer serves the
    # site and the sitemap was never fetched. It has to follow the runtime host.
    assert robots_body =~ "Sitemap: #{base}/sitemap.xml"

    # A crawler asking specifically for text/plain must not get a 406.
    plain_robots =
      build_conn()
      |> put_req_header("accept", "text/plain")
      |> get("/robots.txt")

    assert response(plain_robots, 200) =~ "Sitemap: #{base}/sitemap.xml"

    # /tag and /category stay crawlable, so their links still count, but they must
    # not compete with the articles they list.
    tag_document = build_conn() |> get("/tag/spectre?lang=it") |> html_document(200)

    assert one?(tag_document, ~s(meta[name="robots"][content="noindex,follow"]))

    first = get(build_conn(), "/it")
    [etag] = get_resp_header(first, "etag")

    second =
      build_conn()
      |> put_req_header("if-none-match", etag)
      |> get("/it")

    assert response(second, 304) == ""
  end

  test "serves a secret-free health response", %{conn: conn} do
    assert %{
             "status" => "ok",
             "commit" => nil,
             "content_sync" => %{
               "status" => "not_started",
               "last_finished_at" => nil,
               "duration_ms" => nil,
               "error" => nil
             }
           } = conn |> get("/health") |> json_response(200)
  end

  defp html_document(conn, status) do
    conn
    |> html_response(status)
    |> LazyHTML.from_document()
  end

  defp one?(document, selector), do: document |> LazyHTML.query(selector) |> Enum.count() == 1

  defp sitemap_entry(xml, url) do
    [entry] =
      Regex.run(
        ~r/<url>\s*<loc>#{Regex.escape(url)}<\/loc>.*?<\/url>/s,
        xml,
        capture: :first
      )

    entry
  end

  defp article(title, slug, language, status, opts \\ []) do
    category = Keyword.get(opts, :category)
    tags = Keyword.get(opts, :tags, [])
    translation_of = Keyword.get(opts, :translation_of)
    cover = Keyword.get(opts, :cover)
    cover_alt = Keyword.get(opts, :cover_alt)
    body = Keyword.get(opts, :body, "Testo dell'articolo.")

    optional =
      [
        category && "category: #{category}",
        cover && "cover: #{cover}",
        cover_alt && "cover_alt: #{cover_alt}",
        translation_of && "translation_of: #{translation_of}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    """
    ---
    title: #{title}
    slug: #{slug}
    lang: #{language}
    status: #{status}
    date: 2026-08-03
    tags: #{Jason.encode!(tags)}
    #{optional}
    ---
    #{body}
    """
  end

  defp temporary_directory do
    path =
      Path.join(
        System.tmp_dir!(),
        "ex-blog-web-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end
end
