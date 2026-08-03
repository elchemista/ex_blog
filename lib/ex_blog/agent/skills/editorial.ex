defmodule ExBlog.Agent.Skills.Editorial do
  @moduledoc """
  Editorial capability with a persistent, multi-turn article creation flow.

  The nested creation flows describe the current field being collected. A
  completed intake is converted to Action Language and validated by Kinetic
  before Spectre stages the protected repository mutation.
  """

  use Spectre.Skill,
    id: :editorial,
    version: 1,
    prompt_root: "lib/ex_blog_web/prompts/skills/editorial"

  alias ExBlog.Agent.KineticActions
  alias ExBlog.Config
  alias ExBlog.Content
  alias Spectre.Action
  alias Spectre.ActionConfig
  alias Spectre.ActionPlanner
  alias Spectre.Context
  alias Spectre.Input
  alias Spectre.Result
  alias Spectre.Runner
  alias Spectre.State

  @workflow_key :article_creation
  @creation_flows [:article_title, :article_category, :article_language, :article_brief]

  requires_action(:create_article, mode: :write)
  requires_action(:revise_article, mode: :write)
  requires_action(:translate_article, mode: :write)
  requires_action(:generate_seo, mode: :write)
  requires_action(:publish_article, mode: :write)
  requires_action(:unpublish_article, mode: :write)
  requires_action(:delete_article, mode: :destructive)

  policy :editorial_confirmation do
    request(:confirm_editorial_action)
    accept(:approved, regex: ~r/^(?:s[iì]|yes|confermo)$/iu)
    reject(:rejected, regex: ~r/^(?:no|annulla|cancel)$/iu)
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

  interrupt :CANCEL_ARTICLE_CREATION,
    regex:
      ~r/^\s*(?:\/cancel|annulla|lascia\s+(?:stare|perdere)|stop|cancel|never\s*mind)\s*[.!]?\s*$/iu,
    cache: false do
    run(:cancel_creation)
  end

  flow :editorial do
    flow :article_creation do
      on :START_ARTICLE_CREATION,
        regex:
          ~r/^(?:\/create(?:\s|$)|(?:(?:scrivi|crea)(?:mi)?|write|create)\s+(?:un\s+|an?\s+)?(?:articolo|post)\b)/iu,
        cache: false do
        run(:start_creation)
      end

      flow :article_title do
        on :CAPTURE_ARTICLE_TITLE, via: [:llm_classifier], cache: false do
          run(:capture_title)
        end
      end

      flow :article_category do
        on :CAPTURE_ARTICLE_CATEGORY, via: [:llm_classifier], cache: false do
          run(:capture_category)
        end
      end

      flow :article_language do
        on :CAPTURE_ARTICLE_LANGUAGE, via: [:llm_classifier], cache: false do
          run(:capture_language)
        end
      end

      flow :article_brief do
        on :CAPTURE_ARTICLE_BRIEF, via: [:llm_classifier], cache: false do
          run(:capture_brief)
        end
      end
    end

    flow :article_changes do
      on :REVISE_ARTICLE, regex: ~r/^(?:\/revise|rivedi|revisiona|riscrivi)/iu do
        act(:editorial_turn_prompt, intelligence: :balanced)
      end

      on :TRANSLATE_ARTICLE, regex: ~r/^(?:\/translate|traduci)/iu do
        act(:editorial_turn_prompt, intelligence: :balanced)
      end

      on :GENERATE_ARTICLE_SEO, regex: ~r/^(?:\/seo|genera.*seo)/iu do
        act(:editorial_turn_prompt, intelligence: :balanced)
      end

      on :PUBLISH_ARTICLE, regex: ~r/^(?:\/publish|pubblica)/iu do
        act(:editorial_turn_prompt, intelligence: :balanced)
      end

      on :UNPUBLISH_ARTICLE, regex: ~r/^(?:\/unpublish|ritira|depubblica)/iu do
        act(:editorial_turn_prompt, intelligence: :balanced)
      end

      on :DELETE_ARTICLE,
        regex: ~r/^(?:\/delete|elimina|cancella).*(?:articolo|post)?/iu do
        act(:editorial_turn_prompt, intelligence: :balanced)
      end
    end
  end

  @doc false
  @spec start_creation(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def start_creation(%Input{} = input, %Context{} = ctx) do
    advance(input, ctx, :article_title, %{}, :article_title_request)
  end

  @doc false
  @spec capture_title(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def capture_title(%Input{text: text} = input, %Context{} = ctx) do
    case bounded_field(text, 160) do
      {:ok, title} ->
        workflow = ctx |> workflow() |> Map.put(:title, title)

        advance(input, ctx, :article_category, workflow, :article_category_request,
          category_options: category_options()
        )

      {:error, _reason} ->
        invalid_field(input, ctx, "titolo", 160)
    end
  end

  @doc false
  @spec capture_category(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def capture_category(%Input{text: text} = input, %Context{} = ctx) do
    case bounded_field(text, 80) do
      {:ok, category} ->
        workflow = ctx |> workflow() |> Map.put(:category, category)

        advance(input, ctx, :article_language, workflow, :article_language_request,
          languages: Enum.join(Config.get().supported_languages, ", ")
        )

      {:error, _reason} ->
        invalid_field(input, ctx, "categoria", 80)
    end
  end

  @doc false
  @spec capture_language(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def capture_language(%Input{text: text} = input, %Context{} = ctx) do
    language = text |> String.trim() |> String.downcase()

    if language in Config.get().supported_languages do
      workflow = ctx |> workflow() |> Map.put(:lang, language)
      advance(input, ctx, :article_brief, workflow, :article_brief_request)
    else
      invalid_field(input, ctx, "lingua", 32,
        allowed: Enum.join(Config.get().supported_languages, ", ")
      )
    end
  end

  @doc false
  @spec capture_brief(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def capture_brief(%Input{text: text} = input, %Context{} = ctx) do
    case bounded_field(text, 8_000) do
      {:ok, brief} ->
        workflow = ctx |> workflow() |> Map.put(:brief, brief)
        stage_creation(input, ctx, workflow)

      {:error, _reason} ->
        invalid_field(input, ctx, "brief", 8_000)
    end
  end

  @doc false
  @spec cancel_creation(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def cancel_creation(%Input{} = input, %Context{} = ctx) do
    if active?(ctx.state) do
      reply(:article_creation_cancelled, input, %{ctx | state: clear_workflow(ctx.state)})
    else
      reply(:no_article_creation, input, ctx)
    end
  end

  @doc false
  @spec cancel_confirmation(Input.t(), Context.t()) :: String.t()
  def cancel_confirmation(_input, _ctx),
    do: "Operazione annullata: conferma non ricevuta."

  @doc false
  @spec active?(State.t()) :: boolean()
  def active?(%State{current_flow: flow, data: data}) do
    flow in @creation_flows and is_map(Map.get(data, @workflow_key))
  end

  @spec stage_creation(Input.t(), Context.t(), map()) ::
          {:ok, Result.t()} | {:error, term()}
  defp stage_creation(input, ctx, workflow) do
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
    state = %{
      ctx.state
      | current_flow: flow,
        current_scope: ctx.route.scope,
        data: Map.put(ctx.state.data, @workflow_key, workflow)
    }

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

  @spec category_options() :: String.t()
  defp category_options do
    Content.list(lang: :all, status: :all)
    |> Enum.map(& &1.category)
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
    |> Enum.sort()
    |> case do
      [] -> "Nessuna categoria esistente: scrivine una nuova."
      categories -> Enum.map_join(categories, "\n", &"- #{&1}")
    end
  end

  @spec creation_command(map()) :: String.t()
  defp creation_command(workflow) do
    KineticActions.create_article_command(
      workflow.title,
      workflow.lang,
      workflow.category,
      workflow.brief
    )
  end
end
