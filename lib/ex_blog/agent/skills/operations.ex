defmodule ExBlog.Agent.Skills.Operations do
  @moduledoc """
  Runtime diagnostics, budget visibility, and repository synchronization.
  """

  use Spectre.Skill,
    id: :operations,
    version: 1,
    prompt_root: "lib/ex_blog_web/prompts/skills/operations"

  requires_action(:show_config, mode: :read)
  requires_action(:openrouter_status, mode: :read)
  requires_action(:budget_status, mode: :read)
  requires_action(:sync_repository, mode: :write)

  policy :repository_confirmation do
    request(:confirm_repository_action)
    accept(:approved, regex: ~r/^(?:yes|confirm)$/iu)
    reject(:rejected, regex: ~r/^(?:no|cancel)$/iu)
    otherwise(ask: :confirm_repository_action)
    attempts(3, then: :cancel_confirmation)
  end

  protect(:sync_repository, with: :repository_confirmation)

  flow :operations do
    flow :runtime do
      on :SHOW_BLOG_CONFIG,
        regex: [
          ~r/^\/config$/iu,
          ~r/(?:show|display).*(?:configuration|config)/iu
        ],
        embedding: ["show the safe blog configuration", "display the agent configuration"],
        learn: true do
        action(:show_config, args: %{})
      end

      on :SHOW_AI_BUDGET,
        regex: [
          ~r/^\/budget$/iu,
          ~r/(?:budget|spend|spent|costs?)/iu
        ],
        embedding: ["show the AI budget", "how much has the agent spent"],
        learn: true do
        action(:budget_status, args: %{})
      end

      on :CHECK_OPENROUTER,
        regex: ~r/openrouter.*(?:status|configured|working|available)/iu,
        embedding: ["check whether OpenRouter is available", "show the OpenRouter status"],
        learn: true do
        action(:openrouter_status, args: %{})
      end
    end

    flow :repository do
      on :SYNC_BLOG_REPOSITORY,
        regex: [~r/^\/sync$/iu, ~r/(?:sync|update).*(?:repository|repo)/iu] do
        act(:sync_repository_prompt, intelligence: :balanced)
      end
    end
  end

  @doc false
  @spec cancel_confirmation(Spectre.Input.t(), Spectre.Context.t()) :: String.t()
  def cancel_confirmation(_input, _ctx),
    do: "Operation cancelled because confirmation was not received."
end
