defmodule ExBlog.Agent.PageAuditTest do
  use ExUnit.Case, async: true

  alias ExBlog.Agent.PageAudit
  alias SpectreLens.View

  test "audits a rendered page inside Lens trust boundaries and closes browser resources" do
    view = valid_view()

    assessor = fn prompt ->
      send(self(), {:assessment_prompt, prompt})
      {:ok, "Result: OK\nThe page passes every observable check."}
    end

    assert {:ok, audit} =
             PageAudit.check("https://example.com/article?preview=1",
               lens: ExBlog.TestLens,
               lens_opts: [test_pid: self(), view: view],
               assessor: assessor,
               focus: "check accessibility and SEO"
             )

    assert audit.url == "https://example.com/article"
    assert audit.title == "A useful article"
    assert audit.baseline_ok?
    assert audit.issues == []
    assert audit.metrics.h1_count == 1
    assert audit.metrics.structured_data?
    refute audit.metrics.visual_rendering?
    assert audit.assessment =~ "Result: OK"
    assert Enum.any?(audit.warnings, &String.contains?(&1, "pixel-level"))

    assert_receive {:assessment_prompt, prompt}
    assert prompt =~ "--- BEGIN UNTRUSTED WEB CONTENT ---"
    assert prompt =~ "check accessibility and SEO"
    assert prompt =~ "Header, main content, and footer are present."
    refute prompt =~ "session=secret"
    refute prompt =~ "preview=1"

    assert_receive {:lens, {:open, open_opts}}
    assert open_opts[:network_policy] == :public
    assert_receive {:lens, {:new_tab, [url: "https://example.com/article?preview=1"]}}
    assert_receive {:lens, {:look, look_opts}}
    assert :semantic_tree in look_opts[:include]
    assert_receive {:lens, :zoom_out}
    assert_receive {:lens, :close_tab}
    assert_receive {:lens, :close}
  end

  test "reports deterministic defects and still returns the model assessment" do
    view = %View{
      url: "https://example.com/broken",
      title: "",
      markdown: "Broken page",
      html: "<html><body><h1>First</h1><h1>Second</h1><img src=\"cover.jpg\"></body></html>",
      errors: [:semantic_projection_failed]
    }

    assert {:ok, audit} =
             PageAudit.check("https://example.com/broken",
               lens: ExBlog.TestLens,
               lens_opts: [test_pid: self(), view: view],
               assessor: fn _prompt -> "Result: ISSUES\nFix the metadata." end
             )

    refute audit.baseline_ok?
    assert "The document title is missing." in audit.issues
    assert "Expected exactly one h1; found 2." in audit.issues
    assert "1 image has no alt attribute." in audit.issues
    assert Enum.any?(audit.issues, &String.contains?(&1, "semantic_projection_failed"))
  end

  test "closes the tab and runtime when page perception fails" do
    assert {:error, :look_failed} =
             PageAudit.check("https://example.com/failure",
               lens: ExBlog.TestLens,
               lens_opts: [
                 test_pid: self(),
                 view: valid_view(),
                 look_result: {:error, :look_failed}
               ],
               assessor: fn _prompt -> flunk("assessment must not run") end
             )

    assert_receive {:lens, :close_tab}
    assert_receive {:lens, :close}
  end

  test "keeps the deterministic audit when qualitative assessment is unavailable" do
    assert {:ok, audit} =
             PageAudit.check("https://example.com/article",
               lens: ExBlog.TestLens,
               lens_opts: [test_pid: self(), view: valid_view()],
               assessor: fn _prompt -> {:error, :budget_exceeded} end
             )

    assert audit.baseline_ok?
    assert audit.assessment =~ "unavailable"
    assert Enum.any?(audit.warnings, &String.contains?(&1, "budget_exceeded"))
  end

  test "rejects malformed and credential-bearing URLs before opening a browser" do
    assert {:error, :invalid_page_url} = PageAudit.check("javascript:alert(1)")
    assert {:error, :invalid_page_url} = PageAudit.check("https://user:pass@example.com")
    assert {:error, :invalid_page_url} = PageAudit.check("https://example.com/a path")
    refute_received {:lens, _message}
  end

  defp valid_view do
    %View{
      url: "https://example.com/article?session=secret",
      title: "A useful article",
      markdown: "# A useful article\n\nReadable content.",
      semantic_tree: %{role: "document"},
      semantic_text: "A useful article. Readable content.",
      interactive: [%{role: "link"}],
      forms: [],
      links: [%{href: "https://example.com/next"}],
      structured_data: %{"jsonLd" => [%{"@type" => "Article"}]},
      html: """
      <!doctype html>
      <html lang="en">
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="description" content="A useful summary">
          <meta property="og:title" content="A useful article">
          <meta property="og:description" content="A useful summary">
          <link href="https://example.com/article" rel="canonical">
        </head>
        <body><main><h1>A useful article</h1><img src="cover.jpg" alt="Cover"></main></body>
      </html>
      """
    }
  end
end
