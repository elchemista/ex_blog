defmodule ExBlog.Agent.Skills.EditorialTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Agent
  alias ExBlog.Agent.Actions
  alias ExBlog.Content.Index
  alias ExBlog.Telegram.Image
  alias Spectre.Beam.Content
  alias Spectre.Beam.Inbound
  alias Spectre.Result
  alias SpectreLens.View

  defmodule StartCreationClassifier do
    @moduledoc false

    # Deterministic stand-in for the optional trained classifier: tests speak
    # plain English, and this stub supplies the confident intent prediction
    # that a trained artifact or the LLM classifier would produce.
    def classify(_text, _opts) do
      {:ok,
       %{
         label: "START_ARTICLE_CREATION",
         accepted?: true,
         confidence: 0.97,
         margin: 0.2,
         strategy: :local_classifier
       }}
    end
  end

  test "the source-grounded flow researches, previews, revises, and approves one Git draft" do
    conversation_id = conversation_id()

    assert {:ok, started} = start_creation(conversation_id)
    assert started.route.label == :START_ARTICLE_CREATION
    assert started.route.scope == {:skill, :editorial}
    assert started.state.current_flow == :article_sources
    assert started.state.current_scope == {:skill, :editorial}

    assert {:ok, researched} = research_sources(conversation_id)
    assert researched.route.label == :CAPTURE_ARTICLE_SOURCES
    assert researched.route.strategy == :regex
    assert researched.state.current_flow == :article_brief
    assert researched.reply_text =~ "Spectre Lens finished"
    assert researched.reply_text =~ "OTP-native runtime"

    assert {:ok, briefed} =
             ask(
               "Focus on practical architecture, safety boundaries, and Elixir developers.",
               conversation_id
             )

    assert briefed.route.label == :CAPTURE_ARTICLE_BRIEF
    assert briefed.route.strategy == :creation_continuation
    assert briefed.state.current_flow == :article_language

    assert {:ok, localized} = ask("it", conversation_id)
    assert localized.route.label == :CAPTURE_ARTICLE_LANGUAGE
    assert localized.state.current_flow == :article_category

    assert {:ok, categorized} = ask("Elixir", conversation_id)
    assert categorized.route.label == :CAPTURE_ARTICLE_CATEGORY
    assert categorized.state.current_flow == :article_title

    assert {:ok, titled} = ask("Phoenix and Spectre", conversation_id)
    assert titled.route.label == :CAPTURE_ARTICLE_TITLE
    assert titled.state.current_flow == :article_seo

    test_pid = self()

    draft_ai = fn :deep, prompt, opts ->
      send(test_pid, {:draft_prompt, prompt, opts})

      {:ok,
       %{
         text:
           "## Why Spectre\n\nSpectre is an OTP-native runtime.\n\n[Source](https://example.com/spectre)"
       }}
    end

    assert {:ok, preview} = ask("generate SEO", conversation_id, ai_complete: draft_ai)

    assert preview.route.label == :CAPTURE_ARTICLE_SEO
    assert preview.state.current_flow == :article_review
    assert Result.pending_effect(preview) == nil
    assert preview.reply_text =~ "--- DRAFT MARKDOWN ---"
    assert preview.reply_text =~ "Spectre is an OTP-native runtime"
    assert_received {:draft_prompt, draft_prompt, draft_opts}
    assert draft_prompt =~ "Focus on practical architecture"
    assert draft_prompt =~ "OTP-native runtime"
    assert draft_prompt =~ "https://example.com/spectre"
    assert draft_opts[:purpose] == :article_generation

    revision_ai = fn :deep, prompt, opts ->
      send(test_pid, {:revision_prompt, prompt, opts})

      {:ok,
       %{
         text:
           "## Why Spectre\n\nSpectre is an explicit OTP-native runtime for safe agents.\n\n[Source](https://example.com/spectre)"
       }}
    end

    assert {:ok, revised} =
             ask(
               "modify: make the safety boundary more explicit",
               conversation_id,
               ai_complete: revision_ai
             )

    assert revised.route.label == :CAPTURE_ARTICLE_REVIEW
    assert revised.route.strategy == :regex
    assert revised.state.current_flow == :article_review
    assert revised.state.data.article_creation.revision_count == 1
    assert revised.reply_text =~ "Draft revision 1"
    assert revised.reply_text =~ "explicit OTP-native runtime"
    assert_received {:revision_prompt, revision_prompt, revision_opts}
    assert revision_prompt =~ "make the safety boundary more explicit"
    assert revision_opts[:purpose] == :article_revision

    assert {:ok, staged} = ask("confirm", conversation_id)

    assert staged.route.label == :CAPTURE_ARTICLE_REVIEW
    assert staged.route.strategy == :regex
    assert staged.state.current_flow == nil
    assert staged.state.current_scope == nil
    refute Map.has_key?(staged.state.data, :article_creation)

    effect = Result.pending_effect(staged)
    assert effect.name == :create_article
    assert effect.owner == ExBlog.Agent.Skills.Editorial
    assert effect.scope == {:skill, :editorial}
    assert effect.status == :approved
    assert effect.policy == {{:skill, :editorial}, :editorial_confirmation}

    assert effect.args["title"] == "Phoenix and Spectre"
    assert effect.args["category"] == "Elixir"
    assert effect.args["lang"] == "it"

    assert effect.args["brief"] ==
             "Focus on practical architecture, safety boundaries, and Elixir developers."

    assert effect.args["generate_seo"]
    assert effect.args["body"] =~ "explicit OTP-native runtime"
    assert effect.args["research_summary"] =~ "OTP-native runtime"
    assert effect.args["source_urls"] == "https://example.com/spectre"
    assert Result.open_awaitable(staged) == nil
  end

  test "category and title can be generated by OpenRouter inside their nested flows" do
    conversation_id = conversation_id()

    assert {:ok, _started} = start_creation(conversation_id)
    assert {:ok, _researched} = research_sources(conversation_id)
    assert {:ok, _briefed} = ask("A practical guide to Spectre flows.", conversation_id)
    assert {:ok, _localized} = ask("it", conversation_id)
    test_pid = self()

    category_ai = fn :fast, prompt, opts ->
      send(test_pid, {:category_prompt, prompt, opts})
      {:ok, %{text: "Artificial intelligence"}}
    end

    assert {:ok, categorized} =
             ask("generate category", conversation_id, ai_complete: category_ai)

    assert categorized.state.current_flow == :article_title
    assert_received {:category_prompt, category_prompt, category_opts}
    assert category_prompt =~ "A practical guide to Spectre flows."
    assert category_opts[:purpose] == :category_generation

    title_ai = fn :balanced, prompt, opts ->
      send(test_pid, {:title_prompt, prompt, opts})
      {:ok, %{text: ~s("Spectre flows for reliable editorial teams")}}
    end

    assert {:ok, titled} = ask("generate title", conversation_id, ai_complete: title_ai)
    assert titled.state.current_flow == :article_seo
    assert titled.reply_text =~ "Spectre flows for reliable editorial teams"
    assert titled.reply_text =~ "generated with OpenRouter"
    assert_received {:title_prompt, title_prompt, title_opts}
    assert title_prompt =~ "Artificial intelligence"
    assert title_opts[:purpose] == :title_generation

    draft_ai = fn :deep, _prompt, opts ->
      assert opts[:purpose] == :article_generation
      {:ok, %{text: "## Draft\n\nA source-grounded article."}}
    end

    assert {:ok, preview} = ask("skip", conversation_id, ai_complete: draft_ai)
    assert preview.state.current_flow == :article_review
    refute preview.state.data.article_creation.generate_seo
    assert Result.pending_effect(preview) == nil
  end

  test "cancelling a generated preview clears it without staging a repository write" do
    conversation_id = conversation_id()

    assert {:ok, _started} = start_creation(conversation_id)
    assert {:ok, _researched} = research_sources(conversation_id)

    for answer <- [
          "Explain the architecture to experienced Elixir developers.",
          "en",
          "Engineering",
          "A reviewed Spectre architecture"
        ] do
      assert {:ok, _result} = ask(answer, conversation_id)
    end

    assert {:ok, preview} =
             ask("skip", conversation_id,
               ai_complete: fn :deep, _prompt, _opts ->
                 {:ok, %{text: "## Preview\n\nNo repository write yet."}}
               end
             )

    assert preview.state.current_flow == :article_review
    assert Result.pending_effect(preview) == nil

    assert {:ok, cancelled} =
             ask("cancel", conversation_id,
               article_writer: fn _params ->
                 flunk("cancellation must never invoke the writer")
               end
             )

    assert cancelled.route.label == :CANCEL_ARTICLE_CREATION
    assert cancelled.state.current_flow == nil
    refute Map.has_key?(cancelled.state.data, :article_creation)
    assert Result.pending_effect(cancelled) == nil
  end

  test "an authenticated Telegram photo is saved without advancing the active flow" do
    conversation_id = conversation_id()
    root = temporary_directory()
    bytes = <<0xFF, 0xD8, 0xFF, 0xE0, "telegram-cover">>
    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, _started} = start_creation(conversation_id)
    assert {:ok, input} = Image.prepare(image_inbound(conversation_id, byte_size(bytes)))

    downloader = fn _session_id, {:file_id, 77}, _opts -> {:ok, %{bytes: bytes}} end

    assert {:ok, attached} =
             ask(input, conversation_id,
               telegram_media_downloader: downloader,
               article_asset_root: root
             )

    assert attached.route.label == :ATTACH_ARTICLE_IMAGE
    assert attached.state.current_flow == :article_sources
    workflow = attached.state.data.article_creation
    assert workflow.cover_alt == "Spectre and Kinetic diagram"
    assert workflow.cover =~ "/images/articles/"
    assert attached.reply_text =~ workflow.cover
    assert attached.reply_text =~ "committed to Git together"
    assert [_stored] = File.ls!(root)

    assert {:ok, _researched} = research_sources(conversation_id)

    for answer <- [
          "Explain how the system handles Telegram covers.",
          "en",
          "Engineering",
          "Telegram covers in Spectre"
        ] do
      assert {:ok, _result} = ask(answer, conversation_id)
    end

    assert {:ok, _preview} =
             ask("skip", conversation_id,
               ai_complete: fn :deep, _prompt, _opts ->
                 {:ok, %{text: "## Covers\n\nA reviewed article with a Git-managed cover."}}
               end
             )

    assert {:ok, approved} = ask("confirm", conversation_id)
    effect = Result.pending_effect(approved)
    assert effect.args["cover"] == workflow.cover
    assert effect.args["cover_alt"] == "Spectre and Kinetic diagram"
  end

  test "language names are parsed without an LLM and invalid values keep the active flow" do
    conversation_id = conversation_id()

    assert {:ok, _started} = start_creation(conversation_id)
    assert {:ok, _researched} = research_sources(conversation_id)
    assert {:ok, _briefed} = ask("A complete brief", conversation_id)
    assert {:ok, localized} = ask("English", conversation_id)

    assert localized.route.label == :CAPTURE_ARTICLE_LANGUAGE
    assert localized.route.strategy == :creation_continuation
    assert localized.state.current_flow == :article_category
    assert localized.state.data.article_creation.lang == "en"

    other_conversation_id = conversation_id()
    assert {:ok, _started} = start_creation(other_conversation_id)
    assert {:ok, _researched} = research_sources(other_conversation_id)
    assert {:ok, _briefed} = ask("Another complete brief", other_conversation_id)
    assert {:ok, result} = ask("fr", other_conversation_id)

    assert result.route.label == :CAPTURE_ARTICLE_LANGUAGE
    assert result.state.current_flow == :article_language
    assert result.reply_text =~ "Allowed values: it, en"
  end

  test "the global cancel interrupt clears an active creation flow" do
    conversation_id = conversation_id()

    assert {:ok, _started} = start_creation(conversation_id)
    assert {:ok, _researched} = research_sources(conversation_id)
    assert {:ok, _briefed} = ask("A brief to discard", conversation_id)
    assert {:ok, cancelled} = ask("never mind", conversation_id)

    assert cancelled.route.label == :CANCEL_ARTICLE_CREATION
    assert cancelled.state.current_flow == nil
    assert cancelled.state.current_scope == nil
    refute Map.has_key?(cancelled.state.data, :article_creation)
    assert cancelled.reply_text =~ "cancelled"
  end

  test "a canonical publish command stages a real yes-or-cancel decision without an LLM" do
    root = temporary_directory()
    english = Path.join([root, "content", "en"])
    File.mkdir_p!(english)

    File.write!(
      Path.join(english, "2026-08-04-ready-to-publish.md"),
      """
      ---
      title: Ready to publish
      slug: ready-to-publish
      lang: en
      status: draft
      date: 2026-08-04
      tags: []
      ---
      The article body.
      """
    )

    start_supervised!({Index, root: root, content_root: "content"})
    on_exit(fn -> File.rm_rf!(root) end)
    conversation_id = conversation_id()

    assert {:ok, staged} = ask("publish en/ready-to-publish", conversation_id)
    assert staged.route.label == :PUBLISH_ARTICLE
    assert staged.route.strategy == :regex
    assert staged.reply_text =~ "Publish it now"
    assert staged.reply_text =~ "https://localhost/en/ready-to-publish"
    assert staged.reply_text =~ "Reply “yes”"
    assert Result.open_awaitable(staged) != nil
    assert Result.pending_effect(staged).name == :publish_article

    assert {:ok, cancelled} = ask("cancel", conversation_id)
    assert match?({:cancelled, _reason}, Result.action_outcome(cancelled))
  end

  test "a natural publish request resolves the exact article title without generating AL" do
    root = temporary_directory()
    english = Path.join([root, "content", "en"])
    File.mkdir_p!(english)
    title = "Building a Blog with Spectre: My Library for Agent-Driven Development"
    slug = "building-a-blog-with-spectre-my-library-for-agent-driven-development"

    File.write!(
      Path.join(english, "2026-08-04-#{slug}.md"),
      """
      ---
      title: "#{title}"
      slug: #{slug}
      lang: en
      status: draft
      date: 2026-08-04
      tags: []
      ---
      The article body.
      """
    )

    start_supervised!({Index, root: root, content_root: "content"})
    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, staged} =
             ask(
               "make this article published : #{title}",
               conversation_id(),
               ai_complete: fn _level, _prompt, _opts ->
                 flunk("title-based publication must not ask a model to generate Action Language")
               end
             )

    assert staged.route.label == :PUBLISH_ARTICLE
    assert staged.route.strategy == :regex
    assert staged.reply_text =~ title
    assert staged.reply_text =~ "Publish it now"
    refute staged.reply_text =~ "PUBLISH ARTICLE"

    effect = Result.pending_effect(staged)
    assert effect.name == :publish_article
    assert effect.args == %{"lang" => "en", "slug" => slug}
    assert effect.status == :waiting_policy
  end

  test "a displayed article number starts a review-first edit and approves the exact preview" do
    root = temporary_directory()
    english = Path.join([root, "content", "en"])
    File.mkdir_p!(english)

    File.write!(
      Path.join(english, "2026-08-04-newer.md"),
      indexed_article("Newer article", "newer", "2026-08-04")
    )

    File.write!(
      Path.join(english, "2026-08-03-selected.md"),
      indexed_article("Selected article", "selected", "2026-08-03")
    )

    start_supervised!({Index, root: root, content_root: "content"})
    on_exit(fn -> File.rm_rf!(root) end)
    conversation_id = conversation_id()

    assert {:ok, listed} =
             Actions.list_articles(%{}, %{
               input: %{text: "list articles"},
               state: %{conversation_id: conversation_id}
             })

    assert Enum.map(listed.articles, & &1.slug) == ["newer", "selected"]

    assert {:ok, selected} = ask("edit 2 article", conversation_id)
    assert selected.route.label == :REVISE_ARTICLE
    assert selected.route.strategy == :regex
    assert selected.state.current_flow == :article_revision_instructions
    assert selected.reply_text =~ "Selected article"
    assert selected.reply_text =~ "What would you like to change?"

    ai_complete = fn :deep, prompt, opts ->
      assert prompt =~ "Selected article body."
      assert prompt =~ "Make the introduction more direct"
      assert opts[:purpose] == :article_revision
      {:ok, %{text: "## Revised\n\nA more direct introduction."}}
    end

    assert {:ok, preview} =
             ask("Make the introduction more direct", conversation_id, ai_complete: ai_complete)

    assert preview.route.label == :CAPTURE_ARTICLE_REVISION_INSTRUCTIONS
    assert preview.state.current_flow == :article_revision_review
    assert preview.reply_text =~ "--- REVISED MARKDOWN ---"
    assert preview.reply_text =~ "A more direct introduction."
    assert Result.pending_effect(preview) == nil

    assert {:ok, approved} = ask("confirm", conversation_id)
    assert approved.route.label == :CAPTURE_ARTICLE_REVISION_REVIEW
    assert approved.state.current_flow == nil
    refute Map.has_key?(approved.state.data, :article_revision)

    effect = Result.pending_effect(approved)
    assert effect.name == :revise_article
    assert effect.status == :approved
    assert effect.args["lang"] == "en"
    assert effect.args["slug"] == "selected"
    assert effect.args["proposed_body"] == "## Revised\n\nA more direct introduction."
    assert Result.open_awaitable(approved) == nil
  end

  defp ask(message, conversation_id, opts \\ []) do
    Spectre.ask(Agent, message, Keyword.put(opts, :conversation_id, conversation_id))
  end

  defp start_creation(conversation_id) do
    ask("I want to write a new article", conversation_id,
      classifier_local: StartCreationClassifier
    )
  end

  defp research_sources(conversation_id) do
    ask("https://example.com/spectre?draft=1", conversation_id,
      lens: ExBlog.TestLens,
      lens_opts: [view: source_view()],
      research_summarizer: fn prompt ->
        assert prompt =~ "--- BEGIN UNTRUSTED WEB CONTENT ---"

        {:ok,
         "- Spectre is an OTP-native runtime with explicit routing, state, policies, and effects ([source](https://example.com/spectre)).\n\nNo release version was observed."}
      end
    )
  end

  defp source_view do
    %View{
      url: "https://example.com/spectre?session=secret",
      title: "Spectre",
      markdown:
        "# Spectre\n\nAn OTP-native runtime with explicit routing, state, policies, and effects.",
      semantic_tree: %{role: "document"},
      semantic_text: "Spectre is an OTP-native runtime.",
      links: [],
      structured_data: %{}
    }
  end

  defp image_inbound(conversation_id, size) do
    %Inbound{
      endpoint: :telegram,
      channel_type: :telegram,
      message_id: "image-77",
      conversation_id: conversation_id,
      sender: ExBlog.Config.get().admin_telegram_username,
      content: %Content{
        type: :image,
        text: "Spectre and Kinetic diagram",
        data: %{file_id: 77, size: size},
        metadata: %{}
      },
      authenticated?: true,
      metadata: %{}
    }
  end

  defp temporary_directory do
    path =
      Path.join(
        System.tmp_dir!(),
        "ex-blog-editorial-assets-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end

  defp indexed_article(title, slug, date) do
    """
    ---
    title: #{title}
    slug: #{slug}
    lang: en
    status: draft
    date: #{date}
    tags: []
    ---
    #{title} body.
    """
  end

  defp conversation_id do
    "editorial-skill-#{System.unique_integer([:positive, :monotonic])}"
  end
end
