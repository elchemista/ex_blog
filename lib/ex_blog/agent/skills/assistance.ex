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

  alias Spectre.{Context, Input, Result, Runner}

  flow :assistance do
    on :SHOW_CAPABILITIES,
      embedding: [
        "explain how the ExBlog assistant works",
        "show the available commands and capabilities",
        "what information can I ask this bot for"
      ],
      learn: true,
      via: [:embedding, :classifier, :semantic_cache, :llm_classifier] do
      run(:show_capabilities)
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

  @doc "Renders the deterministic capability menu from the Skill-owned prompt."
  @spec show_capabilities(Input.t(), Context.t()) :: {:ok, Result.t()} | {:error, term()}
  def show_capabilities(%Input{} = input, %Context{} = context) do
    Runner.reply(:capabilities, input, context)
  end
end
