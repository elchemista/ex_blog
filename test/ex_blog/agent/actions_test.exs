defmodule ExBlog.Agent.ActionsTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Agent.Actions
  alias ExBlog.Agent.Presenter
  alias ExBlog.Content.Article

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
end
