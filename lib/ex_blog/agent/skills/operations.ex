defmodule ExBlog.Agent.Skills.Operations do
  @moduledoc """
  Runtime diagnostics, budget visibility, and repository synchronization.

  Diagnostics are cacheable, learnable read routes and therefore use semantic
  examples, the optional local classifier, verified semantic-cache rows, and
  the LLM classifier.
  Repository synchronization is a write route: natural-language routing may
  use optional embeddings, the optional local classifier, or the LLM
  classifier. The route is never learned and Spectre must complete
  `repository_confirmation` before execution.

  The verification flow shows how a skill combines with `Spectre.Work`: a
  natural request starts the durable sync-and-verify procedure on the blog's
  Agent Instance, and a separate cacheable read route reports the committed
  loop view afterwards.

  There are no slash commands here: every request is plain English, and the
  agent's only remaining regex are the safety and cancellation interrupts.
  """

  use Spectre.Skill,
    id: :operations,
    version: 1,
    prompt_root: "lib/ex_blog_web/prompts/skills/operations"

  alias ExBlog.Agent.Works.SyncAndVerify
  alias Spectre.Context
  alias Spectre.Input
  alias Spectre.Result
  alias Spectre.Runner

  requires_action(:show_config, mode: :read)
  requires_action(:openrouter_status, mode: :read)
  requires_action(:budget_status, mode: :read)
  requires_action(:system_status, mode: :read)
  requires_action(:sync_repository, mode: :write)

  # The policy belongs to the skill so its prompts, attempts, and pending state
  # remain scoped to Operations even when more skills define similar policies.
  policy :repository_confirmation do
    request(:confirm_repository_action)
    accept(:approved, regex: ~r/^(?:yes|confirm)$/iu)
    reject(:rejected, regex: ~r/^(?:no|cancel)$/iu)
    otherwise(ask: :confirm_repository_action)
    attempts(3, then: :cancel_confirmation)
  end

  protect(:sync_repository, with: :repository_confirmation)

  # Runtime reads can safely participate in semantic learning. The repository
  # branch below has an intentionally different provider and cache policy.
  flow :operations do
    flow :runtime do
      on :SHOW_BLOG_CONFIG,
        embedding: [
          "show the safe blog configuration",
          "display the agent configuration",
          "which non-secret settings is the blog using"
        ],
        learn: true,
        via: [:embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:show_config, args: %{})
      end

      on :SHOW_AI_BUDGET,
        embedding: [
          "show the AI budget",
          "how much has the agent spent",
          "report the remaining monthly model allowance"
        ],
        learn: true,
        via: [:embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:budget_status, args: %{})
      end

      on :CHECK_OPENROUTER,
        embedding: [
          "check whether OpenRouter is available",
          "show the OpenRouter status",
          "verify that the configured AI models can be reached"
        ],
        learn: true,
        via: [:embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:openrouter_status, args: %{})
      end

      on :SHOW_SYSTEM_STATUS,
        embedding: [
          "show the current ExBlog system status",
          "report whether the application, Telegram, content, and AI services are healthy",
          "give me a complete operational health summary"
        ],
        learn: true,
        via: [:embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:system_status, args: %{})
      end
    end

    flow :repository do
      # `cache: false` prevents a learned phrase from becoming authorization.
      # Routing selects an intent; the confirmation policy grants execution.
      on :SYNC_BLOG_REPOSITORY,
        embedding: [
          "synchronize the blog checkout with its remote repository",
          "fetch the canonical content branch and rebuild the index",
          "refresh local blog content from GitHub"
        ],
        cache: false,
        via: [:embedding, :classifier, :llm_classifier] do
        act(:sync_repository_prompt, intelligence: :balanced)
      end
    end

    flow :verification do
      # Starting the Work is deliberate maintenance, never a learnable read.
      # The handler acknowledges immediately; the Work continues on the
      # operational runtime owned by the blog's Agent Instance.
      on :VERIFY_BLOG,
        embedding: [
          "run a full sync and verification of the published blog",
          "synchronize the content and audit every published page",
          "verify that the whole public site is healthy"
        ],
        cache: false,
        via: [:embedding, :classifier, :llm_classifier] do
        work(SyncAndVerify, input: %{}, reply: :verification_started)
      end

      on :SHOW_VERIFICATION,
        embedding: [
          "show the latest blog verification report",
          "how did the last site verification go",
          "report the results of the sync and audit work"
        ],
        learn: true,
        via: [:embedding, :classifier, :semantic_cache, :llm_classifier] do
        run(:verification_status)
      end
    end
  end

  @doc "Renders the newest sync-and-verify loop view for the administrator."
  @spec verification_status(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def verification_status(%Input{} = input, %Context{} = ctx) do
    with pid when is_pid(pid) <- Keyword.get(ctx.opts, :instance_pid),
         {:ok, views} <- Spectre.loops(pid, kind: :work),
         %{} = view <- newest_verification(views) do
      Runner.reply(:verification_status, input, ctx, assigns: view_assigns(view))
    else
      _unavailable -> Runner.reply(:verification_none, input, ctx, assigns: %{})
    end
  end

  @doc false
  @spec cancel_confirmation(Spectre.Input.t(), Spectre.Context.t()) :: String.t()
  def cancel_confirmation(_input, _ctx),
    do: "Operation cancelled because confirmation was not received."

  defp newest_verification(views) do
    views
    |> Enum.filter(&(&1.definition == :sync_and_verify))
    |> Enum.sort_by(& &1.updated_at, :desc)
    |> List.first()
  end

  defp view_assigns(view) do
    pages = view.partial_results |> List.wrap() |> Enum.filter(&page_result?/1)
    healthy = Enum.count(pages, & &1["ok"])

    %{
      status: status_label(view),
      phase: to_string(view.phase || "unknown"),
      checked: length(pages),
      healthy: healthy,
      unhealthy: length(pages) - healthy,
      issues: issue_lines(pages)
    }
  end

  defp page_result?(%{"url" => _url, "ok" => _ok}), do: true
  defp page_result?(_result), do: false

  defp status_label(%{status: :terminal, terminal_category: :completed}), do: "completed"
  defp status_label(%{status: :terminal, terminal_category: category}), do: to_string(category)
  defp status_label(_view), do: "running"

  defp issue_lines(pages) do
    pages
    |> Enum.reject(& &1["ok"])
    |> Enum.take(5)
    |> Enum.map(fn page ->
      "#{page["url"]}: #{Enum.join(List.wrap(page["issues"]), " ")}"
    end)
  end
end
