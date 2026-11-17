defmodule ExBlogWeb.GovernedActModelControllerTest do
  use ExBlogWeb.ConnCase, async: true

  test "renders the Italian manifesto as a distinct governed document", %{conn: conn} do
    document = conn |> get("/it/governed-act-model") |> html_document(200)
    base = ExBlog.Config.canonical_url()

    assert one?(document, ~s(#governed-act-model[data-manifesto-language="it"]))
    assert text(document, "h1#governed-act-title") == "GOVERNED ACT MODEL"
    assert text(document, "#governed-act-thesis") =~ "L’intelligenza crea possibilità"
    assert one?(document, "#manifesto-primitives")
    assert one?(document, "#manifesto-term-mandate")
    assert one?(document, "#manifesto-term-evidence")
    assert one?(document, "#manifesto-term-act")
    assert one?(document, "#manifesto-term-duty")

    assert one?(document, ~s(#manifesto-body h2[id="media-tutto-ciò-che-conta"]))
    assert one?(document, ~s(#manifesto-body h2[id="lautorità-non-cresce"]))

    assert LazyHTML.text(LazyHTML.query(document, "#manifesto-body")) =~
             "l’intelligenza ha agito sotto governo"

    assert count(document, "h1") == 1
    assert one?(document, ~s(#manifesto-nav-link[aria-current="page"]))
    assert one?(document, ~s(link[rel="canonical"][href="#{base}/it/governed-act-model"]))

    assert one?(
             document,
             ~s(link[rel="alternate"][hreflang="en"][href="#{base}/en/governed-act-model"])
           )

    assert one?(document, ~s(#language-switcher a[hreflang="en"][href="/en/governed-act-model"]))
  end

  test "renders the complete English manifesto and machine-readable metadata", %{conn: conn} do
    document = conn |> get("/en/governed-act-model") |> html_document(200)

    assert one?(document, ~s(html[lang="en"]))

    assert text(document, "#governed-act-thesis") ==
             "Intelligence creates possibilities. Power turns them into consequences."

    assert text(document, "#manifesto-term-mandate") =~ "Where the right to propose"
    assert one?(document, ~s(#manifesto-body h2[id="mediate-everything-that-matters"]))
    assert one?(document, ~s(#manifesto-body h2[id="authority-does-not-grow"]))

    assert LazyHTML.text(LazyHTML.query(document, "#manifesto-body")) =~
             "intelligence acted under governance"

    json_ld =
      document
      |> LazyHTML.query(~s(script[type="application/ld+json"]))
      |> LazyHTML.text()
      |> Jason.decode!()

    assert json_ld["@type"] == "TechArticle"
    assert json_ld["headline"] == "GOVERNED ACT MODEL"
    assert json_ld["inLanguage"] == "en"
    assert json_ld["wordCount"] > 2_000
  end

  test "rejects manifesto languages for which no reviewed source exists", %{conn: conn} do
    document = conn |> get("/fr/governed-act-model") |> html_document(404)

    assert one?(document, "#not-found")
    assert one?(document, ~s(meta[name="robots"][content="noindex,follow"]))
  end

  defp html_document(conn, status) do
    conn
    |> html_response(status)
    |> LazyHTML.from_document()
  end

  defp text(document, selector) do
    document
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
    |> String.trim()
  end

  defp one?(document, selector), do: count(document, selector) == 1
  defp count(document, selector), do: document |> LazyHTML.query(selector) |> Enum.count()
end
