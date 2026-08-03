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
    accept(:approved, regex: ~r/^(?:s[iì]|yes|confermo)$/iu)
    reject(:rejected, regex: ~r/^(?:no|annulla|cancel)$/iu)
    otherwise(ask: :confirm_repository_action)
    attempts(3, then: :cancel_confirmation)
  end

  protect(:sync_repository, with: :repository_confirmation)

  flow :operations do
    flow :runtime do
      on :SHOW_BLOG_CONFIG,
        regex: [~r/^\/config$/iu, ~r/(?:mostra|fammi vedere).*(?:configurazione|config)/iu] do
        action(:show_config, args: %{})
      end

      on :SHOW_AI_BUDGET,
        regex: [~r/^\/budget$/iu, ~r/(?:budget|quanto ho speso|costi?)/iu] do
        action(:budget_status, args: %{})
      end

      on :CHECK_OPENROUTER, regex: ~r/openrouter.*(?:configurato|funziona|status)/iu do
        action(:openrouter_status, args: %{})
      end
    end

    flow :repository do
      on :SYNC_BLOG_REPOSITORY,
        regex: [~r/^\/sync$/iu, ~r/(?:sincronizza|aggiorna).*(?:repository|repo)/iu] do
        act(:sync_repository_prompt, intelligence: :balanced)
      end
    end
  end

  @doc false
  @spec cancel_confirmation(Spectre.Input.t(), Spectre.Context.t()) :: String.t()
  def cancel_confirmation(_input, _ctx),
    do: "Operazione annullata: conferma non ricevuta."
end
