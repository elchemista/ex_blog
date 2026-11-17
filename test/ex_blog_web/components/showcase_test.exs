defmodule ExBlogWeb.ShowcaseTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias ExBlog.Ecosystem.Snapshot
  alias ExBlogWeb.Showcase

  describe "spectre_showcase/1" do
    test "announces the released core version once, from a single source" do
      document = render_showcase(ecosystem: nil)

      assert Showcase.spectre_version() == "0.4.0"
      assert Showcase.spectre_hexdocs_url() =~ Showcase.spectre_version()

      assert LazyHTML.text(document) =~ "hex · #{Showcase.spectre_version()}"
      refute matches?(document, ~s(a[href="https://hexdocs.pm/spectre/0.3.2"]))
    end

    test "lists every satellite library, including the durability and debug ones" do
      catalog = [ecosystem: nil] |> render_showcase() |> LazyHTML.text()

      for library <- ~w(spectre_mnemonic spectre_ledger spectre_kinetic spectre_lens spectre_lab) do
        assert catalog =~ library
      end
    end

    test "shows Server callbacks and human consent through the 0.4 APIs" do
      document = render_showcase(ecosystem: nil)
      sample = text(document, "#spectre-agent-server-example")
      consumer = text(document, "#spectre-governed-example")

      assert sample =~ "def handle_flow("
      assert sample =~ "propose(ctx,"
      assert sample =~ "on_result:"
      assert consumer =~ "Spectre.Server.presented("
      assert consumer =~ "Spectre.Server.decide("
      assert text(document, "#spectre-capabilities-explainer") =~ "GAM Domain"
      assert text(document, "#spectre-evolution") =~ "Verify authority and consent"
      assert text(document, "#spectre-evolution") =~ "Record the outcome"
    end

    test "renders one compatibility row per checked library" do
      document = render_showcase(ecosystem: snapshot())

      assert matches?(document, "#spectre-compatibility")
      assert matches?(document, "#compat-spectre")
      assert matches?(document, "#compat-spectre_lens")

      row = text(document, "#compat-spectre")
      assert row =~ "0.4.0"
      assert row =~ "hex"

      # The outcome is stated in words, so it survives without the colour.
      assert text(document, "#compat-spectre_lens") =~ "failing"
    end

    test "leaves the section out until the first refresh lands" do
      document = render_showcase(ecosystem: nil)

      refute matches?(document, "#spectre-compatibility")
    end
  end

  defp render_showcase(assigns) do
    (&Showcase.spectre_showcase/1)
    |> render_component(assigns)
    |> LazyHTML.from_fragment()
  end

  # `query/2` searches descendants; `filter/2` would only look at the fragment's
  # own root node, which is the showcase <section> itself.
  defp matches?(document, selector) do
    document |> LazyHTML.query(selector) |> Enum.any?()
  end

  defp text(document, selector) do
    document |> LazyHTML.query(selector) |> LazyHTML.text()
  end

  defp snapshot do
    payload = %{
      "generated_at" => "2026-08-16T13:16:15.773486Z",
      "libraries" => [
        %{
          "name" => "spectre",
          "status" => "passing",
          "version" => "0.4.0",
          "version_source" => "hex",
          "repository_url" => "https://github.com/elchemista/spectre",
          "version_url" => "https://hex.pm/packages/spectre"
        },
        %{
          "name" => "spectre_lens",
          "status" => "failing",
          "version" => "0.1.0",
          "version_source" => "github",
          "repository_url" => "https://github.com/elchemista/spectre_lens"
        }
      ]
    }

    {:ok, snapshot} = Snapshot.parse(payload)
    snapshot
  end
end
