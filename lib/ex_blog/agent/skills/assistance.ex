defmodule ExBlog.Agent.Skills.Assistance do
  @moduledoc """
  Help, conversational questions, and editorial inspiration.

  Capability requests receive a deterministic menu. Open-ended questions use
  a bounded reasoning prompt that cannot plan or execute actions; operational
  requests still belong to the dedicated read and mutation routes.
  """

  use Spectre.Skill,
    id: :assistance,
    version: 1,
    prompt_root: "lib/ex_blog_web/prompts/skills/assistance"

  flow :assistance do
    on :SHOW_CAPABILITIES,
      embedding: [
        "explain how the ExBlog assistant works",
        "show the available commands and capabilities",
        "what information can I ask this bot for"
      ],
      learn: true,
      via: [:embedding, :classifier, :semantic_cache, :llm_classifier] do
      reply(:capabilities)
    end

    on :ASK_AI,
      embedding: [
        "help me brainstorm an idea for the blog",
        "answer a general question to give me inspiration",
        "talk through a creative article direction with me"
      ],
      learn: false,
      via: [:embedding, :classifier, :semantic_cache, :llm_classifier] do
      reason(:inspiration,
        intelligence: :balanced,
        maximum_output_tokens: 600,
        temperature: 0.6
      )
    end
  end
end
