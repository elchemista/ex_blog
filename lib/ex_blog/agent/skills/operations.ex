defmodule ExBlog.Agent.Skills.Operations do
  @moduledoc """
  Runtime diagnostics, budget visibility, and repository synchronization.

  Diagnostics are cacheable, learnable read routes and therefore use regex,
  semantic examples, the trained local classifier, verified semantic-cache
  rows, and the LLM classifier.
  Repository synchronization is a write route: natural-language routing may
  use optional embeddings, the trained local classifier, or the LLM classifier,
  while regex remains available for `/sync`. The route is never learned and
  Spectre must complete `repository_confirmation` before execution.

  Regex is deliberately limited to explicit slash commands. Natural-language
  operations belong to the trained classifier, semantic cache, and LLM
  fallback. `regex_strength: :hard` makes an explicit `/sync` decisive without
  turning a weak model candidate into hard evidence.
  """

  use Spectre.Skill,
    id: :operations,
    version: 1,
    prompt_root: "lib/ex_blog_web/prompts/skills/operations"

  requires_action(:show_config, mode: :read)
  requires_action(:openrouter_status, mode: :read)
  requires_action(:budget_status, mode: :read)
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
        regex: ~r/^\/config$/u,
        embedding: [
          "show the safe blog configuration",
          "display the agent configuration",
          "which non-secret settings is the blog using"
        ],
        regex_strength: :hard,
        learn: true,
        via: [:regex, :embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:show_config, args: %{})
      end

      on :SHOW_AI_BUDGET,
        regex: ~r/^\/budget$/u,
        embedding: [
          "show the AI budget",
          "how much has the agent spent",
          "report the remaining monthly model allowance"
        ],
        regex_strength: :hard,
        learn: true,
        via: [:regex, :embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:budget_status, args: %{})
      end

      on :CHECK_OPENROUTER,
        regex: ~r/^\/openrouter$/u,
        embedding: [
          "check whether OpenRouter is available",
          "show the OpenRouter status",
          "verify that the configured AI models can be reached"
        ],
        regex_strength: :hard,
        learn: true,
        via: [:regex, :embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:openrouter_status, args: %{})
      end
    end

    flow :repository do
      # `cache: false` prevents a learned phrase from becoming authorization.
      # Routing selects an intent; the confirmation policy grants execution.
      on :SYNC_BLOG_REPOSITORY,
        regex: ~r/^\/sync$/u,
        embedding: [
          "synchronize the blog checkout with its remote repository",
          "fetch the canonical content branch and rebuild the index",
          "refresh local blog content from GitHub"
        ],
        regex_strength: :hard,
        cache: false,
        via: [:regex, :embedding, :classifier, :llm_classifier] do
        act(:sync_repository_prompt, intelligence: :balanced)
      end
    end
  end

  @doc false
  @spec cancel_confirmation(Spectre.Input.t(), Spectre.Context.t()) :: String.t()
  def cancel_confirmation(_input, _ctx),
    do: "Operation cancelled because confirmation was not received."
end
