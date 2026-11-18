defmodule ExBlogWeb.DocumentationControllerTest do
  use ExBlogWeb.ConnCase, async: true

  alias ExBlog.Documentation

  test "the documentation entry redirects to the canonical language", %{conn: conn} do
    language = ExBlog.Config.get().default_language
    assert redirected_to(get(conn, "/docs")) == "/#{language}/docs"

    assert redirected_to(get(conn, "/docs/routing")) == "/#{language}/docs/routing"
  end

  test "the bilingual catalogue exposes every guide in reading order", %{conn: conn} do
    for language <- Documentation.languages() do
      document = conn |> get("/#{language}/docs") |> html_document(200)
      chapters = Documentation.chapters(language)

      assert Enum.take(Enum.map(chapters, & &1.slug), 5) ==
               ~w(overview getting-started handlers server-callbacks stack-tools)

      assert count(document, "h1") == 1
      assert count(document, "#docs-catalogue li") == length(chapters)
      assert count(document, ~s(#docs-nav-link[aria-current="page"])) == 1
      assert count(document, "#docs-mobile-navigation summary") == 1

      for chapter <- chapters do
        assert count(
                 document,
                 ~s(#docs-card-#{chapter.slug}[href="/#{language}/docs/#{chapter.slug}"])
               ) ==
                 1
      end
    end

    assert Enum.map(Documentation.chapters("it"), & &1.slug) ==
             Enum.map(Documentation.chapters("en"), & &1.slug)
  end

  test "chapters have canonical metadata, usable contents and translated navigation", %{
    conn: conn
  } do
    base = ExBlog.Config.canonical_url()

    for language <- Documentation.languages(), chapter <- Documentation.chapters(language) do
      path = "/#{language}/docs/#{chapter.slug}"
      document = conn |> get(path) |> html_document(200)

      assert count(document, "h1#docs-title") == 1
      assert count(document, "h1") == 1
      assert text(document, "#docs-title") == chapter.title
      assert count(document, ~s(link[rel="canonical"][href="#{base}#{path}"])) == 1

      for locale <- Documentation.languages() do
        assert count(
                 document,
                 ~s(#language-switcher a[hreflang="#{locale}"][href="/#{locale}/docs/#{chapter.slug}"])
               ) == 1
      end

      for section <- chapter.sections do
        assert count(document, ~s(#docs-body h2[id="#{section.id}"])) == 1
      end

      metadata =
        document
        |> LazyHTML.query(~s(script[type="application/ld+json"]))
        |> LazyHTML.text()
        |> Jason.decode!()

      assert metadata["@type"] == "TechArticle"
      assert metadata["version"] == "0.4.0"
      assert metadata["inLanguage"] == language
    end
  end

  test "the callback reference covers the published behaviour in both languages", %{conn: conn} do
    for language <- Documentation.languages() do
      document = conn |> get("/#{language}/docs/server-callbacks") |> html_document(200)

      signatures =
        document
        |> LazyHTML.query("#docs-body table td:first-child code")
        |> Enum.map(&LazyHTML.text/1)

      for {name, arity} <- Spectre.Server.behaviour_info(:callbacks) do
        assert Enum.any?(signatures, fn signature ->
                 case Regex.run(~r/^(\w+)\(([^()]*)\)$/, signature) do
                   [_, function, args] ->
                     function == Atom.to_string(name) and
                       length(String.split(args, ",", trim: true)) == arity

                   _ ->
                     false
                 end
               end),
               "Missing #{name}/#{arity} in #{language}"
      end
    end
  end

  test "unknown languages and chapter paths never expose local files", %{conn: conn} do
    for path <- ["/fr/docs", "/en/docs/not-a-guide", "/it/docs/mix.exs"] do
      response = get(conn, path)
      document = html_document(response, 404)
      assert count(document, "#not-found") == 1
      assert count(document, ~s(meta[name="robots"][content="noindex,follow"])) == 1
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end

    assert Documentation.fetch("en", "../mix.exs") == :error
  end

  test "the first and last chapters have no wrapped pagination", %{conn: conn} do
    first = conn |> get("/en/docs/overview") |> html_document(200)
    last = conn |> get("/en/docs/migration") |> html_document(200)

    assert count(first, "#docs-pagination a") == 1
    assert count(first, ~s(#docs-pagination a[href="/en/docs/getting-started"])) == 1
    assert count(last, "#docs-pagination a") == 1
    assert count(last, ~s(#docs-pagination a[href="/en/docs/testing-production"])) == 1
  end

  test "cache validators distinguish language and chapter", %{conn: conn} do
    english = get(conn, "/en/docs/routing")
    italian = get(conn, "/it/docs/routing")
    other = get(conn, "/en/docs/training")

    assert english.status == 200
    refute get_resp_header(english, "etag") == get_resp_header(italian, "etag")
    refute get_resp_header(english, "etag") == get_resp_header(other, "etag")

    [etag] = get_resp_header(english, "etag")

    assert conn
           |> put_req_header("if-none-match", etag)
           |> get("/en/docs/routing")
           |> response(304) == ""
  end

  test "the sitemap advertises canonical documentation and language alternates", %{conn: conn} do
    xml = conn |> get("/sitemap.xml") |> response(200)
    base = ExBlog.Config.canonical_url()

    for language <- Documentation.languages() do
      assert xml =~ "<loc>#{base}/#{language}/docs</loc>"

      for chapter <- Documentation.chapters(language) do
        assert xml =~ "<loc>#{base}/#{language}/docs/#{chapter.slug}</loc>"
      end
    end

    refute xml =~ "<loc>#{base}/docs</loc>"
  end

  defp html_document(conn, status), do: conn |> html_response(status) |> LazyHTML.from_document()
  defp count(document, selector), do: document |> LazyHTML.query(selector) |> Enum.count()

  defp text(document, selector),
    do: document |> LazyHTML.query(selector) |> LazyHTML.text() |> String.trim()
end
