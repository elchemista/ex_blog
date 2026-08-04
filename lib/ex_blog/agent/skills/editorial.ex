defmodule ExBlog.Agent.Skills.Editorial do
  @moduledoc """
  Editorial capability with a persistent, multi-turn article creation flow.

  The nested flows are the workflow: each leaf captures exactly one editorial
  decision and `Spectre.State.current_flow` persists the cursor between
  Telegram messages. Free text is routed deterministically to that leaf by the
  host router plug, while global interrupts keep natural cancellation phrases
  and Telegram image attachment available at every step.

  Title and category generation are read-only OpenRouter leaf calls. They fill
  state but never touch Git. Once the administrator selects article and SEO
  generation, the completed intake becomes real Action Language, Kinetic
  validates it against the `@al` catalog, and Spectre stages the protected
  repository mutation behind the skill policy.

  Route declarations expose optional embedding similarity, the optional
  local-classifier provider, and the LLM classifier. They deliberately exclude
  `:semantic_cache`: a historical vector match may identify an editorial
  intent, but it must never become a reusable authorization signal for a write.
  There are no bot-style slash commands; the only remaining regex are the
  natural cancellation phrases and the internal Telegram image marker, and
  model evidence stays confidence-gated.
  """

  use Spectre.Skill,
    id: :editorial,
    version: 1,
    prompt_root: "lib/ex_blog_web/prompts/skills/editorial"

  alias ExBlog.Agent.EditorialAI
  alias ExBlog.Agent.KineticActions
  alias ExBlog.Agent.Language
  alias ExBlog.Config
  alias ExBlog.Content
  alias ExBlog.Content.Asset
  alias ExBlog.Telegram.Image
  alias Spectre.Action
  alias Spectre.ActionConfig
  alias Spectre.ActionPlanner
  alias Spectre.Context
  alias Spectre.Input
  alias Spectre.Result
  alias Spectre.Runner
  alias Spectre.State

  @workflow_key :article_creation
  @creation_flows [
    :article_brief,
    :article_language,
    :article_category,
    :article_title,
    :article_seo
  ]

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
    accept(:approved, regex: ~r/^(?:yes|confirm)$/iu)
    reject(:rejected, regex: ~r/^(?:no|cancel)$/iu)
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
    regex: ~r/^\s*(?:stop|cancel|never\s*mind)\s*[.!]?\s*$/iu,
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
    # active, the five child leaves are owned exclusively by CreationContinuation.
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
    end

    # Existing-article operations use natural-language intent routing, then
    # Kinetic converts the request into typed Action Language. Every resulting
    # write still passes through `editorial_confirmation` above.
    flow :article_changes do
      on :REVISE_ARTICLE,
        embedding: [
          "revise an existing article according to new instructions",
          "rewrite part of a published blog post",
          "improve the wording and structure of this draft"
        ],
        cache: false,
        via: [:embedding, :classifier, :llm_classifier] do
        act(:editorial_turn_prompt, intelligence: :balanced)
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
        embedding: [
          "publish a draft article on the public blog",
          "make this post visible to readers",
          "change the article status from draft to published"
        ],
        cache: false,
        via: [:embedding, :classifier, :llm_classifier] do
        act(:editorial_turn_prompt, intelligence: :balanced)
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

  @doc "Starts article intake and asks for the editorial brief."
  @spec start_creation(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def start_creation(%Input{} = input, %Context{} = ctx) do
    advance(input, ctx, :article_brief, %{}, :article_brief_request)
  end

  @doc "Stores the bounded brief and advances intake to language selection."
  @spec capture_brief(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def capture_brief(%Input{text: text} = input, %Context{} = ctx) do
    case bounded_field(text, 8_000) do
      {:ok, brief} ->
        workflow = ctx |> workflow() |> Map.put(:brief, brief)

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

  @doc "Records the SEO choice and stages the protected Kinetic action."
  @spec capture_seo(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def capture_seo(%Input{text: text} = input, %Context{} = ctx) do
    case seo_choice(text) do
      {:ok, generate_seo?} ->
        workflow = ctx |> workflow() |> Map.put(:generate_seo, generate_seo?)
        stage_creation(input, ctx, workflow)

      :error ->
        reply(:article_seo_invalid, input, ctx)
    end
  end

  @doc "Stores an authenticated Telegram image without advancing the flow cursor."
  @spec attach_image(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def attach_image(%Input{} = input, %Context{} = ctx) do
    if active?(ctx.state) do
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

  @doc "Clears an active article-intake workflow without touching the repository."
  @spec cancel_creation(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def cancel_creation(%Input{} = input, %Context{} = ctx) do
    if active?(ctx.state) do
      reply(:article_creation_cancelled, input, %{ctx | state: clear_workflow(ctx.state)})
    else
      reply(:no_article_creation, input, ctx)
    end
  end

  @doc "Returns the reply used when an editorial confirmation exhausts its attempts."
  @spec cancel_confirmation(Input.t(), Context.t()) :: String.t()
  def cancel_confirmation(_input, _ctx),
    do: "Operation cancelled because confirmation was not received."

  @doc "Returns whether persisted Spectre state currently owns an intake leaf."
  @spec active?(State.t()) :: boolean()
  def active?(%State{current_flow: flow, data: data}) do
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

  @spec stage_creation(Input.t(), Context.t(), map()) ::
          {:ok, Result.t()} | {:error, term()}
  defp stage_creation(input, ctx, workflow) do
    workflow = Map.put(workflow, :cover_alt, cover_alt(workflow))
    command = creation_command(workflow)

    planner_opts =
      ActionConfig.planner_opts(ctx,
        effect_owner: ctx.route.owner,
        effect_scope: ctx.route.scope
      )

    with {:ok, effect} <- ActionPlanner.plan(command, ctx, planner_opts) do
      action = Action.from_effect(effect)

      staged_ctx = %{
        ctx
        | state: clear_workflow(ctx.state),
          assigns: Map.put(ctx.assigns, :article_creation, workflow)
      }

      Runner.action({action.via, action.name}, input, staged_ctx,
        args: action.args,
        mode: action.mode,
        planned_by: action.planned_by,
        schema_hash: action.schema_hash,
        al: command,
        reply: :confirm_article_creation
      )
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

  @spec put_workflow(State.t(), map()) :: State.t()
  defp put_workflow(%State{} = state, workflow) do
    %{state | data: Map.put(state.data, @workflow_key, workflow)}
  end

  @spec clear_workflow(State.t()) :: State.t()
  defp clear_workflow(%State{} = state) do
    %{
      state
      | current_flow: nil,
        current_scope: nil,
        data: Map.delete(state.data, @workflow_key)
    }
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

  defp step_instruction(:article_brief), do: "describe the editorial brief"
  defp step_instruction(:article_language), do: "choose the article language"

  defp step_instruction(:article_category),
    do: "enter a category or reply `generate category`"

  defp step_instruction(:article_title), do: "enter a title or reply `generate title`"
  defp step_instruction(:article_seo), do: "reply `generate SEO` or `skip`"
  defp step_instruction(_flow), do: "continue the editorial workflow"

  defp field_label(:category), do: "category"
  defp field_label(:title), do: "title"

  @spec creation_command(map()) :: String.t()
  defp creation_command(workflow) do
    KineticActions.create_article_command(
      workflow.title,
      workflow.lang,
      workflow.category,
      workflow.brief,
      Map.get(workflow, :generate_seo, false),
      Map.get(workflow, :cover),
      Map.get(workflow, :cover_alt)
    )
  end
end
