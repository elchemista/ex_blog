defmodule ExBlog.Agent.ActionsTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Agent.Actions
  alias ExBlog.Agent.Presenter
  alias ExBlog.Content.Article
  alias ExBlog.Content.Index
  alias ExBlog.Ecosystem.Snapshot

  test "article creation generates body and optional SEO before one writer call" do
    ai_complete = fn level, prompt, opts ->
      send(self(), {:ai_call, level, prompt, opts})

      case opts[:purpose] do
        :article_generation ->
          {:ok, %{text: "## Corpo\n\nUn articolo generato."}}

        :seo_generation ->
          {:ok,
           %{
             text:
               Jason.encode!(%{
                 seo_title: "Spectre per redazioni",
                 seo_description: "Un flusso editoriale sicuro e verificabile.",
                 cover_alt: "Descrizione inventata dal modello",
                 tags: ["spectre", "elixir", "workflow"]
               })
           }}
      end
    end

    writer = fn params ->
      send(self(), {:writer_params, params})

      {:ok,
       %Article{
         path: "content/it/2026-08-04-spectre-editoriale.md",
         title: params.title,
         slug: params.slug,
         lang: params.lang,
         status: params.status,
         date: ~D[2026-08-04],
         updated: ~D[2026-08-04],
         category: params.category,
         tags: params.tags,
         seo_title: params.seo_title,
         seo_description: params.seo_description,
         cover: params.cover,
         cover_alt: params.cover_alt,
         body: params.body,
         html: "<h2>Corpo</h2>",
         checksum: "checksum"
       }}
    end

    ctx = %{
      opts: [ai_complete: ai_complete, article_writer: writer],
      state: %{conversation_id: "editorial-test"}
    }

    assert {:ok, result} =
             Actions.create_article(
               %{
                 title: "Spectre editoriale",
                 lang: "it",
                 category: "AI",
                 brief: "Spiega flow, skill, Kinetic e policy.",
                 generate_seo: true,
                 cover: "/images/articles/cover.jpg",
                 cover_alt: "Schema reale del workflow"
               },
               ctx
             )

    assert result.seo_title == "Spectre per redazioni"
    assert result.cover == "/images/articles/cover.jpg"
    assert result.operation == :created

    assert result.source_url ==
             "https://github.com/example/ex-blog-content/blob/main/content/it/2026-08-04-spectre-editoriale.md"

    assert result.public_url == nil

    rendered = Presenter.present(result)
    assert rendered =~ "Draft created and synchronized with Git"
    assert rendered =~ result.source_url
    assert rendered =~ "not public"
    assert_received {:ai_call, :deep, article_prompt, article_opts}
    assert article_prompt =~ "Spiega flow, skill, Kinetic e policy."
    assert article_opts[:purpose] == :article_generation
    assert_received {:ai_call, :balanced, seo_prompt, seo_opts}
    assert seo_prompt =~ "## Corpo"
    assert seo_opts[:purpose] == :seo_generation

    assert_received {:writer_params, params}
    assert params.body == "## Corpo\n\nUn articolo generato."
    assert params.seo_description == "Un flusso editoriale sicuro e verificabile."
    assert params.tags == ["spectre", "elixir", "workflow"]
    assert params.cover_alt == "Schema reale del workflow"
  end

  test "article creation persists the approved preview without regenerating its body" do
    test_pid = self()
    approved_body = "## Reviewed draft\n\nThis is the exact approved Markdown."

    ai_complete = fn _level, _prompt, _opts ->
      flunk("an approved article body must not be regenerated")
    end

    asset_root = temporary_directory()
    on_exit(fn -> File.rm_rf!(asset_root) end)

    writer = fn params, writer_opts ->
      send(test_pid, {:approved_writer_params, params})
      send(test_pid, {:approved_writer_opts, writer_opts})

      {:ok,
       %Article{
         path: "content/en/2026-08-04-reviewed-draft.md",
         title: params.title,
         slug: params.slug,
         lang: params.lang,
         status: params.status,
         date: ~D[2026-08-04],
         category: params.category,
         tags: params.tags,
         body: params.body,
         html: "<h2>Reviewed draft</h2>",
         checksum: "reviewed-checksum"
       }}
    end

    assert {:ok, %{operation: :created}} =
             Actions.create_article(
               %{
                 title: "Reviewed draft",
                 lang: "en",
                 category: "Engineering",
                 body: approved_body,
                 generate_seo: false
               },
               %{
                 opts: [
                   ai_complete: ai_complete,
                   article_writer: writer,
                   article_asset_root: asset_root
                 ],
                 state: %{conversation_id: "approved-preview-test"}
               }
             )

    assert_received {:approved_writer_params, params}
    assert params.body == approved_body
    assert_received {:approved_writer_opts, [asset_source_root: ^asset_root]}
  end

  test "system status combines bounded application, Telegram, OpenRouter, and budget data" do
    ctx = %{
      opts: [
        telegram_snapshot: fn ->
          %{connection_status: :connected, auth_state: :ready, last_error?: false}
        end,
        openrouter_health: fn ->
          {:ok, %{configured: true, reachable: true, models_available: true}}
        end
      ]
    }

    assert {:ok, status} = Actions.system_status(%{}, ctx)
    assert status.system_status
    assert status.application.status == :running
    assert status.telegram.connection_status == :connected
    assert status.telegram.auth_state == :ready
    assert status.openrouter.models_available
    assert is_integer(status.content.indexed_articles)

    rendered = Presenter.present(status)
    assert rendered =~ "System status"
    assert rendered =~ "Telegram: connected"
    assert rendered =~ "OpenRouter: reachable; all models available"
    assert rendered =~ "AI budget remaining: €"
  end

  test "ecosystem synchronization returns every refreshed library for presentation" do
    snapshot = %Snapshot{
      status: :failing,
      summary: %{total: 2, passing: 1, failing: 1},
      generated_at: ~U[2026-08-17 12:00:00Z],
      fetched_at: ~U[2026-08-17 12:01:00Z],
      fingerprint: "fresh",
      libraries: [
        %{
          name: "spectre",
          status: :passing,
          version: "0.3.2",
          source: :hex,
          repository_url: nil,
          version_url: nil,
          run_url: nil
        },
        %{
          name: "spectre_lens",
          status: :failing,
          version: "0.2.0",
          source: :github,
          repository_url: nil,
          version_url: nil,
          run_url: nil
        }
      ]
    }

    ctx = %{opts: [ecosystem_refresh: fn -> {:ok, snapshot} end]}

    assert {:ok, result} = Actions.sync_ecosystem_status(%{}, ctx)
    assert result.ecosystem_status
    assert result.summary.total == 2
    assert Enum.map(result.libraries, & &1.name) == ["spectre", "spectre_lens"]

    rendered = Presenter.present(result)
    assert rendered =~ "home page snapshot was updated"
    assert rendered =~ "spectre: passing 0.3.2 (hex)"
    assert rendered =~ "spectre_lens: failing 0.2.0 (github)"
  end

  test "an unqualified admin list includes drafts and published articles in every language" do
    root = temporary_directory()
    File.mkdir_p!(Path.join([root, "content", "it"]))
    File.mkdir_p!(Path.join([root, "content", "en"]))

    File.write!(
      Path.join([root, "content", "it", "2026-08-04-bozza.md"]),
      article("Bozza", "bozza", "it", "draft")
    )

    File.write!(
      Path.join([root, "content", "en", "2026-08-04-published.md"]),
      article("Published", "published", "en", "published")
    )

    start_supervised!({Index, root: root, content_root: "content"})
    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, %{count: 2, articles: articles}} =
             Actions.list_articles(%{}, %{input: %{text: "list"}})

    assert Enum.map(articles, &{&1.lang, &1.status}) |> Enum.sort() ==
             [{"en", :published}, {"it", :draft}]

    assert {:ok, %{count: 1, articles: [published]}} =
             Actions.list_articles(%{"lang" => "en", "status" => "published"})

    assert published.public_url == "https://localhost/en/published"

    rendered = Presenter.present(%{count: 2, articles: articles})
    assert rendered =~ "2 articles"
    assert rendered =~ "github.com/example/ex-blog-content/blob/main/content/it/"
    assert rendered =~ "https://localhost/en/published"
  end

  defp article(title, slug, lang, status) do
    """
    ---
    title: #{title}
    slug: #{slug}
    lang: #{lang}
    status: #{status}
    date: 2026-08-04
    tags: []
    ---
    Article body.
    """
  end

  defp temporary_directory do
    path =
      Path.join(
        System.tmp_dir!(),
        "ex-blog-actions-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end
end
