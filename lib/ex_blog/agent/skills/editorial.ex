defmodule ExBlog.Agent.Skills.Editorial do
  @moduledoc """
  Editorial capability with a persistent, multi-turn article creation flow.

  The nested flows are the workflow: each leaf captures exactly one editorial
  decision and `Spectre.State.current_flow` persists the cursor between
  Telegram messages. Free text is routed deterministically to that leaf by the
  host router plug, while global interrupts keep natural cancellation phrases
  and Telegram image attachment available at every step.

  Source research, title, category, article preview, and preview revision are
  read-only leaf calls. Source pages cross the Spectre Lens trust boundary and
  only a bounded digest survives in state. Git is touched only after the
  administrator confirms the rendered Markdown preview; that deterministic
  review decision resolves the protected repository action.

  Route declarations expose optional embedding similarity, the optional
  local-classifier provider, and the LLM classifier. They deliberately exclude
  `:semantic_cache`: a historical vector match may identify an editorial
  intent, but it must never become a reusable authorization signal for a write.
  Regex remains limited to hard controls, the internal Telegram image marker,
  URL recognition at the source-intake cursor, and explicit preview decisions.
  """

  use Spectre.Skill,
    id: :editorial,
    version: 1,
    prompt_root: "lib/ex_blog_web/prompts/skills/editorial"

  alias ExBlog.Agent.ArticleSelector
  alias ExBlog.Agent.EditorialAI
  alias ExBlog.Agent.EditorialResearch
  alias ExBlog.Agent.Language
  alias ExBlog.Config
  alias ExBlog.Content
  alias ExBlog.Content.Asset
  alias ExBlog.Telegram.Image
  alias Spectre.Context
  alias Spectre.Input
  alias Spectre.Policy
  alias Spectre.Result
  alias Spectre.Runner
  alias Spectre.State

  @workflow_key :article_creation
  @revision_key :article_revision
  @creation_flows [
    :article_sources,
    :article_brief,
    :article_language,
    :article_category,
    :article_title,
    :article_seo,
    :article_review
  ]
  @revision_flows [:article_revision_instructions, :article_revision_review]
  @source_url_regex ~r{https?://[^\s<>"'`]+}iu

  # These declarations are capability requirements, not direct function calls.
  # The host agent must bind every name to an Action Provider before compilation.
  requires_action(:create_article, mode: :write)
  requires_action(:revise_article, mode: :write)
  requires_action(:translate_article, mode: :write)
  requires_action(:generate_seo, mode: :write)
  requires_action(:publish_article, mode: :write)
  requires_action(:unpublish_article, mode: :write)
  requires_action(:delete_article, mode: :destructive)

  # All repository mutations share one skill-scoped confirmation protocol.
  # Routing only stages an effect; a separate administrator turn approves it.
  policy :editorial_confirmation do
    request(:confirm_editorial_action)
    accept(:approved, regex: ~r/^(?:yes|confirm|si|sì|conferma)$/iu)
    reject(:rejected, regex: ~r/^(?:no|cancel|annulla)$/iu)
    otherwise(ask: :confirm_editorial_action)
    attempts(3, then: :cancel_confirmation)
  end

  protect(:create_article, with: :editorial_confirmation)
  protect(:revise_article, with: :editorial_confirmation)
  protect(:translate_article, with: :editorial_confirmation)
  protect(:generate_seo, with: :editorial_confirmation)
  protect(:publish_article, with: :editorial_confirmation)
  protect(:unpublish_article, with: :editorial_confirmation)
  protect(:delete_article, with: :editorial_confirmation)

  # Cancellation is regex-only because it is a hard control, not an intent
  # that should be inferred or learned from a vaguely similar sentence. The
  # accepted phrases are natural words, not bot commands.
  interrupt :CANCEL_ARTICLE_CREATION,
    regex: ~r/^\s*(?:stop|cancel|never\s*mind|annulla|cancella|lascia\s*perdere)\s*[.!]?\s*$/iu,
    via: [:regex],
    cache: false do
    run(:cancel_creation)
  end

  # Beam turns an authenticated Telegram photo into this private intent. As a
  # global interrupt it wins over whichever free-text field currently owns the
  # conversation, then returns to that same leaf after storing the asset.
  interrupt :ATTACH_ARTICLE_IMAGE,
    regex: ~r/^\/attach-image$/u,
    via: [:regex],
    cache: false do
    run(:attach_image)
  end

  flow :editorial do
    # The parent route starts the workflow through normal intent routing. Once
    # active, child leaves are owned exclusively by CreationContinuation.
    flow :article_creation do
      on :START_ARTICLE_CREATION,
        embedding: [
          "start a guided workflow for a new blog article",
          "help me prepare and write a new post",
          "begin creating a fresh editorial draft"
        ],
        via: [:embedding, :classifier, :llm_classifier],
        cache: false do
        run(:start_creation)
      end

      # The regex is evaluated only by CreationContinuation while this exact
      # cursor is active. It cannot steal an arbitrary URL from reader or audit
      # routes outside article intake.
      flow :article_sources do
        on :CAPTURE_ARTICLE_SOURCES,
          regex: ~r{https?://[^\s<>"'`]+}iu,
          regex_strength: :hard,
          cache: false,
          via: [:creation_continuation] do
          run(:capture_sources)
        end
      end

      # Capture leaves intentionally expose only the custom continuation
      # provider. Hiding them from the global LLM classifier prevents an
      # out-of-flow message from being classified as an arbitrary field answer.
      flow :article_brief do
        on :CAPTURE_ARTICLE_BRIEF, cache: false, via: [:creation_continuation] do
          run(:capture_brief)
        end
      end

      flow :article_language do
        on :CAPTURE_ARTICLE_LANGUAGE, cache: false, via: [:creation_continuation] do
          run(:capture_language)
        end
      end

      flow :article_category do
        on :CAPTURE_ARTICLE_CATEGORY, cache: false, via: [:creation_continuation] do
          run(:capture_category)
        end
      end

      flow :article_title do
        on :CAPTURE_ARTICLE_TITLE, cache: false, via: [:creation_continuation] do
          run(:capture_title)
        end
      end

      flow :article_seo do
        on :CAPTURE_ARTICLE_SEO, cache: false, via: [:creation_continuation] do
          run(:capture_seo)
        end
      end

      flow :article_review do
        on :CAPTURE_ARTICLE_REVIEW,
          regex:
            ~r/^\s*(?:(?:yes|confirm|save|approve|si|sì|conferma|salva|approva)|(?:no|cancel|discard|annulla|cancella|scarta)|(?:modify|change|revise|edit|modifica|cambia|rivedi)\b.*)\s*[.!]?\s*$/iu,
          regex_strength: :hard,
          cache: false,
          via: [:creation_continuation] do
          run(:capture_review)
        end
      end
    end

    # Existing-article operations use natural-language intent routing, then
    # Kinetic converts the request into typed Action Language. Every resulting
    # write still passes through `editorial_confirmation` above.
    flow :article_changes do
      on :REVISE_ARTICLE,
        regex: ~r/^\s*(?:(?:edit|revise)\b.+|update\s+(?:article|post)\b.+)\s*$/iu,
        regex_strength: :hard,
        embedding: [
          "revise an existing article according to new instructions",
          "rewrite part of a published blog post",
          "improve the wording and structure of this draft"
        ],
        cache: false,
        via: [:regex, :embedding, :classifier, :llm_classifier] do
        run(:start_revision)
      end

      flow :article_revision_instructions do
        on :CAPTURE_ARTICLE_REVISION_INSTRUCTIONS,
          cache: false,
          via: [:creation_continuation] do
          run(:capture_revision_instructions)
        end
      end

      flow :article_revision_review do
        on :CAPTURE_ARTICLE_REVISION_REVIEW,
          regex:
            ~r/^\s*(?:(?:yes|confirm|save|approve|si|sì|conferma|salva|approva)|(?:no|cancel|discard|annulla|cancella|scarta)|(?:modify|change|revise|edit|modifica|cambia|rivedi)\b.*)\s*[.!]?\s*$/iu,
          regex_strength: :hard,
          cache: false,
          via: [:creation_continuation] do
          run(:capture_revision_review)
        end
      end

      on :TRANSLATE_ARTICLE,
        embedding: [
          "translate an existing article into another language",
          "create a localized draft from this post",
          "make an Italian version of the English article"
        ],
        cache: false,
        via: [:embedding, :classifier, :llm_classifier] do
        act(:editorial_turn_prompt, intelligence: :balanced)
      end

      on :GENERATE_ARTICLE_SEO,
        embedding: [
          "generate search metadata for an existing article",
          "optimize this post title and description for SEO",
          "add tags and accessible metadata to the draft"
        ],
        cache: false,
        via: [:embedding, :classifier, :llm_classifier] do
        act(:editorial_turn_prompt, intelligence: :balanced)
      end

      on :PUBLISH_ARTICLE,
        regex:
          ~r/^\s*(?:publish\b.+|make\s+(?:this|the)\s+(?:article|post)\s+(?:published|public|live)\s*[:\-]\s*.+)\s*$/iu,
        regex_strength: :hard,
        embedding: [
          "publish a draft article on the public blog",
          "make this post visible to readers",
          "change the article status from draft to published"
        ],
        cache: false,
        via: [:regex, :embedding, :classifier, :llm_classifier] do
        run(:stage_publication)
      end

      on :UNPUBLISH_ARTICLE,
        embedding: [
          "unpublish an article and return it to draft",
          "hide this post from public readers",
          "remove the published status without deleting the content"
        ],
        cache: false,
        via: [:embedding, :classifier, :llm_classifier] do
        act(:editorial_turn_prompt, intelligence: :balanced)
      end

      on :DELETE_ARTICLE,
        embedding: [
          "permanently delete an article from the content repository",
          "remove this blog post and its Markdown file",
          "erase an obsolete editorial draft"
        ],
        cache: false,
        via: [:embedding, :classifier, :llm_classifier] do
        act(:editorial_turn_prompt, intelligence: :balanced)
      end
    end
  end

  @doc "Starts article intake and asks for one to three research URLs."
  @spec start_creation(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def start_creation(%Input{text: text} = input, %Context{} = ctx) do
    topic = text |> Config.redact() |> String.trim() |> String.slice(0, 2_000)
    advance(input, ctx, :article_sources, %{topic: topic}, :article_sources_request)
  end

  @doc "Researches URL input with Spectre Lens and asks for the editorial direction."
  @spec capture_sources(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def capture_sources(%Input{text: text} = input, %Context{} = ctx) do
    with {:ok, urls} <- source_urls(text),
         {:ok, research} <- EditorialResearch.collect(urls, research_options(ctx)) do
      workflow =
        ctx
        |> workflow()
        |> Map.put(:sources, research.sources)
        |> Map.put(:research_summary, research.summary)
        |> Map.put(:research_warnings, research.warnings)

      advance(input, ctx, :article_brief, workflow, :article_research_summary,
        summary: research.summary,
        sources: formatted_sources(research.sources),
        warnings: formatted_warnings(research.warnings)
      )
    else
      {:error, {:too_many_source_urls, maximum}} ->
        reply(:article_sources_invalid, input, ctx, maximum: maximum)

      {:error, reason}
      when reason in [:source_url_required, :invalid_source_url, :invalid_source_urls] ->
        reply(:article_sources_invalid, input, ctx, maximum: 3)

      {:error, _reason} ->
        reply(:article_sources_failed, input, ctx)
    end
  end

  @doc "Stores the bounded brief and advances intake to language selection."
  @spec capture_brief(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def capture_brief(%Input{text: text} = input, %Context{} = ctx) do
    case bounded_field(text, 8_000) do
      {:ok, brief} ->
        workflow =
          ctx
          |> workflow()
          |> Map.put(:directions, brief)
          |> then(&Map.put(&1, :brief, generation_brief(&1)))

        advance(input, ctx, :article_language, workflow, :article_language_request,
          languages: Enum.join(Config.get().supported_languages, ", ")
        )

      {:error, _reason} ->
        invalid_field(input, ctx, "brief", 8_000)
    end
  end

  @doc "Validates one configured language and advances intake to category."
  @spec capture_language(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def capture_language(%Input{text: text} = input, %Context{} = ctx) do
    supported = Config.get().supported_languages

    case Language.parse(text, supported) do
      {:ok, language} ->
        workflow = ctx |> workflow() |> Map.put(:lang, language)

        advance(input, ctx, :article_category, workflow, :article_category_request,
          category_options: category_options()
        )

      :error ->
        invalid_field(input, ctx, "language", 32, allowed: Enum.join(supported, ", "))
    end
  end

  @doc "Stores or generates a category, then advances intake to the title step."
  @spec capture_category(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def capture_category(%Input{text: text} = input, %Context{} = ctx) do
    if generate_request?(text, :category) do
      generate_category(input, ctx)
    else
      case bounded_field(text, 80) do
        {:ok, category} -> continue_after_category(input, ctx, category, false)
        {:error, _reason} -> invalid_field(input, ctx, "category", 80)
      end
    end
  end

  @doc "Stores or generates a title, then advances intake to the SEO choice."
  @spec capture_title(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def capture_title(%Input{text: text} = input, %Context{} = ctx) do
    if generate_request?(text, :title) do
      generate_title(input, ctx)
    else
      case bounded_field(text, 160) do
        {:ok, title} -> continue_after_title(input, ctx, title, false)
        {:error, _reason} -> invalid_field(input, ctx, "title", 160)
      end
    end
  end

  @doc "Records the SEO choice and generates a reviewable Markdown preview."
  @spec capture_seo(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def capture_seo(%Input{text: text} = input, %Context{} = ctx) do
    case seo_choice(text) do
      {:ok, generate_seo?} ->
        workflow = ctx |> workflow() |> Map.put(:generate_seo, generate_seo?)
        prepare_review(input, ctx, workflow)

      :error ->
        reply(:article_seo_invalid, input, ctx)
    end
  end

  @doc "Confirms, revises, or discards the in-memory article preview."
  @spec capture_review(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def capture_review(%Input{text: text} = input, %Context{} = ctx) do
    case review_decision(text) do
      :confirm -> approve_creation(input, ctx)
      :cancel -> cancel_creation(input, ctx)
      {:modify, instructions} -> revise_review(input, ctx, instructions)
      :invalid -> reply(:article_review_invalid, input, ctx)
    end
  end

  @doc "Stores an authenticated Telegram image without advancing the flow cursor."
  @spec attach_image(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def attach_image(%Input{} = input, %Context{} = ctx) do
    if creation_active?(ctx.state) do
      with {:ok, downloaded} <- Image.download(input, ctx.opts),
           {:ok, asset} <- Asset.store(downloaded.bytes, asset_options(ctx)) do
        workflow =
          ctx
          |> workflow()
          |> Map.put(:cover, asset.public_path)
          |> Map.put(:cover_alt, downloaded.caption)

        state = put_workflow(ctx.state, workflow)

        reply(:article_image_attached, input, %{ctx | state: state},
          cover: asset.public_path,
          next_step: step_instruction(state.current_flow)
        )
      else
        {:error, _reason} -> reply(:article_image_failed, input, ctx)
      end
    else
      reply(:article_image_requires_creation, input, ctx)
    end
  end

  @doc "Clears an active creation or revision workflow without touching the repository."
  @spec cancel_creation(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def cancel_creation(%Input{} = input, %Context{} = ctx) do
    case active_workflow(ctx.state) do
      :creation ->
        reply(:article_creation_cancelled, input, %{
          ctx
          | state: clear_creation_workflow(ctx.state)
        })

      :revision ->
        reply(:article_revision_cancelled, input, %{
          ctx
          | state: clear_revision_workflow(ctx.state)
        })

      nil ->
        reply(:no_article_creation, input, ctx)
    end
  end

  @doc "Returns the reply used when an editorial confirmation exhausts its attempts."
  @spec cancel_confirmation(Input.t(), Context.t()) :: String.t()
  def cancel_confirmation(_input, _ctx),
    do: "Operation cancelled because confirmation was not received."

  @doc "Selects an existing article and starts a deterministic revision workflow."
  @spec start_revision(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def start_revision(%Input{text: text} = input, %Context{} = ctx) do
    case select_article(text, ctx) do
      {:ok, article} ->
        revision = %{
          lang: article.lang,
          slug: article.slug,
          title: article.title,
          status: article.status,
          original_body: article.body,
          proposed_body: article.body,
          revision_count: 0
        }

        case initial_revision_instructions(text) do
          {:ok, instructions} -> prepare_article_revision(input, ctx, revision, instructions)
          :missing -> ask_for_revision_instructions(input, ctx, revision)
          {:error, _reason} -> reply(:article_revision_instructions_invalid, input, ctx)
        end

      {:error, reason} ->
        article_selection_failed(:edit, reason, input, ctx)
    end
  end

  @doc "Captures revision instructions for the selected numbered, linked, or named article."
  @spec capture_revision_instructions(Input.t(), Context.t()) ::
          {:ok, Result.t()} | {:error, term()}
  def capture_revision_instructions(%Input{text: text} = input, %Context{} = ctx) do
    case bounded_field(text, 8_000) do
      {:ok, instructions} ->
        prepare_article_revision(input, ctx, revision_workflow(ctx), instructions)

      {:error, _reason} ->
        reply(:article_revision_instructions_invalid, input, ctx)
    end
  end

  @doc "Confirms, modifies, or discards an existing-article revision preview."
  @spec capture_revision_review(Input.t(), Context.t()) ::
          {:ok, Result.t()} | {:error, term()}
  def capture_revision_review(%Input{text: text} = input, %Context{} = ctx) do
    case review_decision(text) do
      :confirm ->
        approve_revision(input, ctx)

      :cancel ->
        cancel_creation(input, ctx)

      {:modify, instructions} ->
        prepare_article_revision(input, ctx, revision_workflow(ctx), instructions)

      :invalid ->
        reply(:article_revision_review_invalid, input, ctx)
    end
  end

  @doc "Stages a selected draft for publication without model-generated Action Language."
  @spec stage_publication(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def stage_publication(%Input{text: text} = input, %Context{} = ctx) do
    case select_article(text, ctx) do
      {:ok, %{status: :draft} = article} ->
        Runner.action(:publish_article, input, ctx,
          args: %{"lang" => article.lang, "slug" => article.slug},
          mode: :write,
          reply: :confirm_article_publication,
          assigns: %{
            title: article.title,
            lang: article.lang,
            slug: article.slug,
            public_url: Config.public_article_url(article.lang, article.slug)
          }
        )

      {:ok, %{status: :published} = article} ->
        reply(:article_already_published, input, ctx,
          title: article.title,
          lang: article.lang,
          slug: article.slug,
          public_url: Config.public_article_url(article.lang, article.slug)
        )

      {:error, reason} ->
        article_selection_failed(:publish, reason, input, ctx)
    end
  end

  @doc "Returns whether persisted Spectre state owns a creation or revision leaf."
  @spec active?(State.t()) :: boolean()
  def active?(%State{} = state), do: not is_nil(active_workflow(state))

  defp creation_active?(%State{current_flow: flow, data: data}) do
    flow in @creation_flows and is_map(Map.get(data, @workflow_key))
  end

  defp generate_category(input, ctx) do
    options = category_options()

    case EditorialAI.category(workflow(ctx), options, ctx) do
      {:ok, category} -> continue_after_category(input, ctx, category, true)
      {:error, _reason} -> generation_failed(:category, input, ctx)
    end
  end

  defp generate_title(input, ctx) do
    case EditorialAI.title(workflow(ctx), ctx) do
      {:ok, title} -> continue_after_title(input, ctx, title, true)
      {:error, _reason} -> generation_failed(:title, input, ctx)
    end
  end

  defp continue_after_category(input, ctx, category, generated?) do
    workflow =
      ctx
      |> workflow()
      |> Map.put(:category, category)
      |> mark_generated(:category, generated?)

    advance(input, ctx, :article_title, workflow, :article_title_request, category: category)
  end

  defp continue_after_title(input, ctx, title, generated?) do
    workflow =
      ctx
      |> workflow()
      |> Map.put(:title, title)
      |> mark_generated(:title, generated?)

    advance(input, ctx, :article_seo, workflow, :article_seo_request,
      title: title,
      title_generated?: generated?
    )
  end

  defp generation_failed(field, input, ctx) do
    reply(:article_generation_failed, input, ctx, field: field_label(field))
  end

  defp prepare_review(input, ctx, workflow) do
    workflow = Map.put(workflow, :cover_alt, cover_alt(workflow))

    case EditorialAI.draft(workflow, ctx) do
      {:ok, body} ->
        workflow =
          workflow
          |> Map.put(:proposed_body, body)
          |> Map.put(:revision_count, 0)

        advance(input, ctx, :article_review, workflow, :article_draft_review,
          title: workflow.title,
          body: body,
          revision_count: 0,
          sources: formatted_sources(Map.get(workflow, :sources, []))
        )

      {:error, _reason} ->
        reply(:article_draft_generation_failed, input, ctx)
    end
  end

  defp revise_review(input, ctx, instructions) do
    with {:ok, instructions} <- bounded_field(instructions, 8_000),
         workflow <- workflow(ctx),
         {:ok, body} <- EditorialAI.revise(workflow, instructions, ctx) do
      revision_count = Map.get(workflow, :revision_count, 0) + 1

      workflow =
        workflow
        |> Map.put(:proposed_body, body)
        |> Map.put(:revision_count, revision_count)
        |> Map.put(:last_revision_instructions, instructions)

      advance(input, ctx, :article_review, workflow, :article_draft_review,
        title: workflow.title,
        body: body,
        revision_count: revision_count,
        sources: formatted_sources(Map.get(workflow, :sources, []))
      )
    else
      {:error, reason} when reason in [:blank, :too_long] ->
        reply(:article_review_invalid, input, ctx)

      {:error, _reason} ->
        reply(:article_revision_failed, input, ctx)
    end
  end

  defp ask_for_revision_instructions(input, ctx, revision) do
    advance_revision(
      input,
      ctx,
      :article_revision_instructions,
      revision,
      :article_revision_instructions_request,
      title: revision.title,
      lang: revision.lang,
      slug: revision.slug,
      status: revision.status
    )
  end

  defp prepare_article_revision(input, ctx, revision, instructions) do
    with {:ok, instructions} <- bounded_field(instructions, 8_000),
         {:ok, body} <- EditorialAI.revise(revision, instructions, ctx) do
      revision_count = Map.get(revision, :revision_count, 0) + 1

      revision =
        revision
        |> Map.put(:proposed_body, body)
        |> Map.put(:revision_count, revision_count)
        |> Map.put(:last_revision_instructions, instructions)

      advance_revision(
        input,
        ctx,
        :article_revision_review,
        revision,
        :article_revision_preview,
        title: revision.title,
        lang: revision.lang,
        slug: revision.slug,
        body: body,
        revision_count: revision_count
      )
    else
      {:error, reason} when reason in [:blank, :too_long] ->
        reply(:article_revision_instructions_invalid, input, ctx)

      {:error, _reason} ->
        reply(:existing_article_revision_failed, input, ctx)
    end
  end

  defp approve_revision(input, ctx) do
    revision = revision_workflow(ctx)

    staged_ctx = %{
      ctx
      | state: clear_revision_workflow(ctx.state),
        assigns: Map.put(ctx.assigns, :article_revision, revision)
    }

    args = %{
      "lang" => Map.get(revision, :lang),
      "slug" => Map.get(revision, :slug),
      "instructions" => Map.get(revision, :last_revision_instructions, "Approved preview"),
      "proposed_body" => Map.get(revision, :proposed_body)
    }

    with {:ok, staged} <-
           Runner.action(:revise_article, input, staged_ctx,
             args: args,
             mode: :write,
             reply: :confirm_article_revision
           ),
         approval_ctx <- %{ctx | state: staged.state},
         {:ok, approved} <- Policy.resolve({:accept, :approved}, input, approval_ctx) do
      {:ok, %{approved | route: ctx.route}}
    end
  end

  defp approve_creation(input, ctx) do
    workflow = workflow(ctx)

    staged_ctx = %{
      ctx
      | state: clear_creation_workflow(ctx.state),
        assigns: Map.put(ctx.assigns, :article_creation, workflow)
    }

    with {:ok, staged} <-
           Runner.action(:create_article, input, staged_ctx,
             args: creation_args(workflow),
             mode: :write,
             reply: :confirm_article_creation
           ),
         approval_ctx <- %{ctx | state: staged.state},
         {:ok, approved} <- Policy.resolve({:accept, :approved}, input, approval_ctx) do
      {:ok, %{approved | route: ctx.route}}
    end
  end

  @spec advance(Input.t(), Context.t(), atom(), map(), atom(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  defp advance(input, ctx, flow, workflow, prompt, assigns \\ []) do
    state =
      ctx.state
      |> put_workflow(workflow)
      |> Map.put(:current_flow, flow)
      |> Map.put(:current_scope, ctx.route.scope)

    reply(prompt, input, %{ctx | state: state}, assigns)
  end

  defp advance_revision(input, ctx, flow, revision, prompt, assigns) do
    state =
      ctx.state
      |> put_revision_workflow(revision)
      |> Map.put(:current_flow, flow)
      |> Map.put(:current_scope, ctx.route.scope)

    reply(prompt, input, %{ctx | state: state}, assigns)
  end

  @spec invalid_field(Input.t(), Context.t(), String.t(), pos_integer(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  defp invalid_field(input, ctx, field, maximum, extra \\ []) do
    assigns = Keyword.merge([field: field, maximum: maximum], extra)
    reply(:article_field_invalid, input, ctx, assigns)
  end

  @spec reply(atom(), Input.t(), Context.t(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  defp reply(prompt, input, ctx, assigns \\ []) do
    Runner.reply(prompt, input, ctx, assigns: Map.new(assigns))
  end

  @spec workflow(Context.t()) :: map()
  defp workflow(%Context{state: %State{data: data}}) do
    case Map.get(data, @workflow_key) do
      workflow when is_map(workflow) -> workflow
      _missing -> %{}
    end
  end

  defp revision_workflow(%Context{state: %State{data: data}}) do
    case Map.get(data, @revision_key) do
      revision when is_map(revision) -> revision
      _missing -> %{}
    end
  end

  @spec put_workflow(State.t(), map()) :: State.t()
  defp put_workflow(%State{} = state, workflow) do
    %{state | data: Map.put(state.data, @workflow_key, workflow)}
  end

  defp put_revision_workflow(%State{} = state, revision) do
    %{state | data: Map.put(state.data, @revision_key, revision)}
  end

  defp clear_creation_workflow(%State{} = state) do
    %{
      state
      | current_flow: nil,
        current_scope: nil,
        data: Map.delete(state.data, @workflow_key)
    }
  end

  defp clear_revision_workflow(%State{} = state) do
    %{
      state
      | current_flow: nil,
        current_scope: nil,
        data: Map.delete(state.data, @revision_key)
    }
  end

  defp active_workflow(%State{current_flow: flow, data: data}) do
    cond do
      flow in @creation_flows and is_map(Map.get(data, @workflow_key)) -> :creation
      flow in @revision_flows and is_map(Map.get(data, @revision_key)) -> :revision
      true -> nil
    end
  end

  @spec bounded_field(String.t(), pos_integer()) :: {:ok, String.t()} | {:error, atom()}
  defp bounded_field(text, maximum) do
    value = String.trim(text)

    cond do
      value == "" -> {:error, :blank}
      String.length(value) > maximum -> {:error, :too_long}
      true -> {:ok, value}
    end
  end

  defp generate_request?(text, field) do
    value = text |> String.trim() |> String.downcase()
    field_name = if field == :title, do: "title", else: "category"

    Regex.match?(
      ~r/^\/?(?:generate|propose|choose|create)(?:\s+(?:the|a|an))?(?:\s+#{field_name})?[.!]?$/iu,
      value
    ) or
      Regex.match?(~r/^(?:you\s+choose|choose|decide)\s+for\s+me[.!]?$/iu, value)
  end

  defp seo_choice(text) do
    value = text |> String.trim() |> String.downcase()

    cond do
      Regex.match?(
        ~r/^(?:\/?generate(?:\s+the)?(?:\s+seo)?|seo|yes)[.!]?$/iu,
        value
      ) ->
        {:ok, true}

      Regex.match?(~r/^(?:skip|without\s+seo|no)[.!]?$/iu, value) ->
        {:ok, false}

      true ->
        :error
    end
  end

  defp source_urls(text) do
    urls =
      @source_url_regex
      |> Regex.scan(text)
      |> Enum.map(&List.first/1)
      |> Enum.map(&Regex.replace(~r/[.,;:!?\)\]\}]+$/u, &1, ""))
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    cond do
      urls == [] -> {:error, :source_url_required}
      length(urls) > 3 -> {:error, {:too_many_source_urls, 3}}
      true -> {:ok, urls}
    end
  end

  defp research_options(ctx) do
    options =
      ctx.opts
      |> Keyword.take([:lens, :lens_opts, :ai_complete, :req_options])
      |> Keyword.put(:topic, Map.get(workflow(ctx), :topic, "New article"))
      |> Keyword.put(:conversation_id, conversation_id(ctx))

    case Keyword.get(ctx.opts, :research_summarizer) do
      fun when is_function(fun, 1) -> Keyword.put(options, :summarizer, fun)
      _default -> options
    end
  end

  defp review_decision(text) do
    value = String.trim(text)

    cond do
      Regex.match?(
        ~r/^(?:yes|confirm|save|approve|si|sì|conferma|salva|approva)\s*[.!]?$/iu,
        value
      ) ->
        :confirm

      Regex.match?(
        ~r/^(?:no|cancel|discard|stop|annulla|cancella|scarta)\s*[.!]?$/iu,
        value
      ) ->
        :cancel

      value == "" ->
        :invalid

      true ->
        instructions =
          value
          |> String.replace(
            ~r/^\s*(?:modify|change|revise|edit|modifica|cambia|rivedi)\s*[:,-]?\s*/iu,
            ""
          )
          |> String.trim()

        if instructions == "", do: :invalid, else: {:modify, instructions}
    end
  end

  defp generation_brief(workflow) do
    """
    Initial topic: #{Map.get(workflow, :topic, "")}
    Editorial directions: #{Map.get(workflow, :directions, "")}
    Spectre Lens research summary: #{Map.get(workflow, :research_summary, "")}
    Sources:
    #{formatted_sources(Map.get(workflow, :sources, []))}
    """
    |> String.trim()
    |> String.slice(0, 8_000)
  end

  defp creation_args(workflow) do
    %{
      "title" => Map.get(workflow, :title),
      "lang" => Map.get(workflow, :lang),
      "category" => Map.get(workflow, :category),
      "brief" => Map.get(workflow, :directions) || Map.get(workflow, :brief),
      "body" => Map.get(workflow, :proposed_body),
      "research_summary" => Map.get(workflow, :research_summary),
      "source_urls" => source_url_lines(workflow),
      "generate_seo" => Map.get(workflow, :generate_seo, false),
      "cover" => Map.get(workflow, :cover) || "",
      "cover_alt" => Map.get(workflow, :cover_alt) || ""
    }
  end

  defp source_url_lines(workflow) do
    workflow
    |> Map.get(:sources, [])
    |> Enum.map(fn source -> Map.get(source, :url) || Map.get(source, "url") end)
    |> Enum.filter(&is_binary/1)
    |> Enum.join("\n")
  end

  defp formatted_sources([]), do: "- none"

  defp formatted_sources(sources) do
    Enum.map_join(sources, "\n", fn source ->
      title = Map.get(source, :title) || Map.get(source, "title") || "Untitled source"
      url = Map.get(source, :url) || Map.get(source, "url") || "[invalid-url]"
      "- #{title} — #{url}"
    end)
  end

  defp formatted_warnings([]), do: ""
  defp formatted_warnings(warnings), do: Enum.map_join(warnings, "\n", &"- #{&1}")

  defp conversation_id(%Context{state: %{conversation_id: value}}) when not is_nil(value),
    do: to_string(value)

  defp conversation_id(_ctx), do: nil

  defp select_article(text, ctx) do
    ArticleSelector.resolve(text, conversation_id: conversation_id(ctx))
  end

  defp article_selection_failed(operation, reason, input, ctx) do
    {message, articles} = selection_failure_details(reason)

    reply(:article_selection_failed, input, ctx,
      operation: operation,
      message: message,
      choices: selection_choices(articles)
    )
  end

  defp selection_failure_details(:article_list_required) do
    {"There is no numbered article list for this conversation yet.", available_articles()}
  end

  defp selection_failure_details({:article_number_out_of_range, number}) do
    {"Article number #{number} is not present in the latest list.", available_articles()}
  end

  defp selection_failure_details(:stale_article_selection) do
    {"That numbered item is stale because the article is no longer indexed.",
     available_articles()}
  end

  defp selection_failure_details({:ambiguous_article, articles}) do
    {"More than one indexed article matches that reference.", articles}
  end

  defp selection_failure_details(_reason) do
    {"No indexed article matches that title, ID, slug, or link.", available_articles()}
  end

  defp available_articles do
    Content.list(lang: :all, status: :all) |> Enum.take(10)
  end

  defp selection_choices([]), do: "No articles are currently indexed."

  defp selection_choices(articles) do
    Enum.map_join(articles, "\n", fn article ->
      "- #{article.lang}/#{article.slug} — #{article.title} (#{article.status})"
    end)
  end

  defp initial_revision_instructions(text) do
    if ArticleSelector.selection_number(text) do
      case Regex.run(
             ~r/^\s*(?:edit|revise|update)\s+(?:article\s+)?#?\d+(?:\s+(?:article|post))?\s*(?::|--)\s*(.+?)\s*$/iu,
             text,
             capture: :all_but_first
           ) do
        [instructions] -> bounded_field(instructions, 8_000)
        _missing -> :missing
      end
    else
      :missing
    end
  end

  @spec category_options() :: String.t()
  defp category_options do
    Content.list(lang: :all, status: :all)
    |> Enum.map(& &1.category)
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
    |> Enum.sort()
    |> case do
      [] -> "No existing categories. Create a clear new category."
      categories -> Enum.map_join(categories, "\n", &"- #{&1}")
    end
  end

  defp mark_generated(workflow, _field, false), do: workflow

  defp mark_generated(workflow, field, true) do
    Map.update(workflow, :ai_fields, [field], fn fields -> Enum.uniq([field | fields]) end)
  end

  defp cover_alt(%{cover_alt: value}) when is_binary(value) and value != "", do: value
  defp cover_alt(%{cover: cover, title: title}) when is_binary(cover), do: "Cover for #{title}"
  defp cover_alt(_workflow), do: nil

  defp asset_options(%Context{opts: opts}) do
    case Keyword.get(opts, :article_asset_root) do
      root when is_binary(root) -> [root: root]
      _default -> []
    end
  end

  defp step_instruction(:article_sources), do: "send one to three public source URLs"
  defp step_instruction(:article_brief), do: "describe the desired angle and instructions"
  defp step_instruction(:article_language), do: "choose the article language"

  defp step_instruction(:article_category),
    do: "enter a category or reply `generate category`"

  defp step_instruction(:article_title), do: "enter a title or reply `generate title`"
  defp step_instruction(:article_seo), do: "reply `generate SEO` or `skip`"
  defp step_instruction(:article_review), do: "confirm, request a modification, or cancel"
  defp step_instruction(_flow), do: "continue the editorial workflow"

  defp field_label(:category), do: "category"
  defp field_label(:title), do: "title"
end
