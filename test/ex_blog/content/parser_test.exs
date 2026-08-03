defmodule ExBlog.Content.ParserTest do
  use ExUnit.Case, async: true

  alias ExBlog.Content.Parser

  test "parses complete front matter and sanitizes unsafe HTML" do
    markdown = """
    ---
    title: "OTP senza paura"
    slug: otp-senza-paura
    lang: it
    status: published
    date: 2026-08-03
    updated: 2026-08-04
    category: elixir
    tags: [otp, phoenix]
    seo_title: "OTP senza paura"
    seo_description: "Una guida pratica"
    cover: assets/2026/08/otp.webp
    cover_alt: "Diagramma OTP"
    ---
    # Introduzione

    <script>alert("no")</script>
    """

    assert {:ok, article} =
             Parser.parse(markdown, "content/it/2026-08-03-otp-senza-paura.md")

    assert article.title == "OTP senza paura"
    assert article.status == :published
    assert article.date == ~D[2026-08-03]
    assert article.tags == ["otp", "phoenix"]
    assert article.html =~ "<h1>Introduzione</h1>"
    refute article.html =~ "<script"
    assert article.excerpt =~ "Introduzione"
    refute article.excerpt =~ "script"
    refute article.excerpt =~ "alert"
  end

  test "uses tolerant defaults for optional editorial fields" do
    markdown = """
    ---
    status: draft
    ---
    Corpo dell'articolo.
    """

    assert {:ok, article} =
             Parser.parse(markdown, "content/en/2026-08-03-an-inferred-title.md")

    assert article.title == "An inferred title"
    assert article.slug == "an-inferred-title"
    assert article.lang == "en"
    assert article.date == ~D[2026-08-03]
    assert article.updated == ~D[2026-08-03]
    assert article.tags == []
  end

  test "returns structured errors for malformed content" do
    assert {:error, :missing_or_malformed_front_matter} =
             Parser.parse("# no front matter", "content/it/nope.md")

    assert {:error, {:invalid_status, "archived"}} =
             Parser.parse(
               "---\nstatus: archived\n---\nBody",
               "content/it/2026-08-03-nope.md"
             )
  end
end
