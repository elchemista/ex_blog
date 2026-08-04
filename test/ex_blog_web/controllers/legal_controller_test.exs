defmodule ExBlogWeb.LegalControllerTest do
  use ExBlogWeb.ConnCase, async: true

  test "serves the Italian cookie policy with consent controls and metadata", %{conn: conn} do
    document = conn |> get("/it/cookies-policy") |> html_document(200)

    assert one?(
             document,
             ~s(#cookie-policy[data-site-domain="spectre.elchemista.com"][data-policy-language="it"])
           )

    assert one?(document, "h1#legal-title")
    assert one?(document, "#cosa-sono")
    assert one?(document, "#base-giuridica")
    assert one?(document, "#legal-contact")
    assert one?(document, ~s(#legal-contact-email[href="mailto:elchemista@gmail.com"]))
    assert one?(document, ~s(#cookie-preferences-button[data-cc="show-preferencesModal"]))
    assert has?(document, ~s(a[href="/it/privacy-policy"]))

    assert one?(
             document,
             ~s(link[rel="canonical"][href="https://spectre.elchemista.com/it/cookies-policy"])
           )
  end

  test "serves the English privacy and GDPR policy", %{conn: conn} do
    document = conn |> get("/en/privacy-policy") |> html_document(200)

    assert one?(
             document,
             ~s(#privacy-policy[data-site-domain="spectre.elchemista.com"][data-policy-language="en"])
           )

    assert one?(document, "#controller")
    assert one?(document, "#data-collected")
    assert one?(document, "#rights")
    assert one?(document, "#complaint")
    assert has?(document, ~s(a[href="/en/cookies-policy"]))

    gdpr_document =
      build_conn()
      |> get("/en/gdpr-policy")
      |> html_document(200)

    assert one?(gdpr_document, "#privacy-policy")

    assert one?(
             gdpr_document,
             ~s(link[rel="canonical"][href="https://spectre.elchemista.com/en/privacy-policy"])
           )
  end

  test "unlocalized legal routes use the configured default language", %{conn: conn} do
    document = conn |> get("/cookies-policy") |> html_document(200)

    assert one?(document, ~s(#cookie-policy[data-policy-language="it"]))
    assert LazyHTML.attribute(LazyHTML.query(document, "html"), "lang") == ["it"]
  end

  test "rejects unsupported policy languages", %{conn: conn} do
    conn = get(conn, "/fr/cookies-policy")
    assert response(conn, 404)
  end

  defp html_document(conn, status) do
    conn
    |> html_response(status)
    |> LazyHTML.from_document()
  end

  defp one?(document, selector), do: document |> LazyHTML.query(selector) |> Enum.count() == 1
  defp has?(document, selector), do: document |> LazyHTML.query(selector) |> Enum.any?()
end
