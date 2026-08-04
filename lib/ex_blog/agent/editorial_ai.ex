defmodule ExBlog.Agent.EditorialAI do
  @moduledoc """
  Bounded OpenRouter helpers used inside the editorial skill's nested flow.

  Spectre remains the workflow owner: this module only fills one requested
  value and never advances state or mutates the content repository. Keeping
  these model calls as leaf operations makes the flow deterministic while
  still letting the administrator request generation at an individual step.

  Prompt construction lives in compiled HEEx templates. Every workflow value
  is redacted, length-limited, and escaped by `ExBlogWeb.Prompt` before it
  reaches OpenRouter.

  These helpers return a single line rather than an article-shaped response.
  That narrow contract makes generated values interchangeable with manual
  answers: after validation, the surrounding skill advances through exactly the
  same state transition in either case.
  """

  alias ExBlog.AI
  alias ExBlogWeb.Prompt
  alias Spectre.Context

  @type workflow :: %{optional(atom()) => term()}

  @doc "Generates one title from the brief already captured by Spectre."
  @spec title(workflow(), Context.t()) :: {:ok, String.t()} | {:error, term()}
  def title(workflow, %Context{} = ctx) when is_map(workflow) do
    prompt = Prompt.editorial_title(workflow)

    generate(:balanced, prompt, :title_generation, 160, ctx)
  end

  @doc "Chooses one category while exposing existing labels as bounded context."
  @spec category(workflow(), String.t(), Context.t()) ::
          {:ok, String.t()} | {:error, term()}
  def category(workflow, category_options, %Context{} = ctx)
      when is_map(workflow) and is_binary(category_options) do
    prompt =
      workflow
      |> Map.put(:category_options, category_options)
      |> Prompt.editorial_category()

    generate(:fast, prompt, :category_generation, 80, ctx)
  end

  defp generate(level, prompt, purpose, maximum, ctx) do
    # Purpose labels drive Prism tier selection and budget reporting. The draft
    # conversation id is used only as an operational subject reference.
    opts = [
      purpose: purpose,
      subject_type: "article_draft",
      subject_ref: conversation_ref(ctx),
      conversation_id: conversation_id(ctx),
      estimated_cost_eur: if(level == :fast, do: "0.005", else: "0.01")
    ]

    with {:ok, response} <- complete(level, prompt, opts, ctx),
         {:ok, text} <- response_text(response) do
      normalize_value(text, maximum)
    end
  end

  defp complete(level, prompt, opts, %Context{opts: context_opts}) do
    case Keyword.get(context_opts, :ai_complete) do
      fun when is_function(fun, 3) -> fun.(level, prompt, opts)
      _default -> AI.complete(level, prompt, opts)
    end
  end

  defp response_text(%{text: text}) when is_binary(text), do: {:ok, text}
  defp response_text(%{"text" => text}) when is_binary(text), do: {:ok, text}
  defp response_text(_response), do: {:error, :invalid_model_response}

  defp normalize_value(text, maximum) do
    value =
      text
      |> String.trim()
      |> String.replace(~r/^```(?:text)?\s*/iu, "")
      |> String.replace(~r/\s*```$/u, "")
      |> String.split(~r/\R/u, trim: true)
      |> List.first()
      |> clean_line()

    cond do
      not is_binary(value) or value == "" -> {:error, :empty_model_value}
      String.length(value) > maximum -> {:error, :model_value_too_long}
      true -> {:ok, value}
    end
  end

  defp clean_line(nil), do: nil

  defp clean_line(line) do
    line
    |> String.trim()
    |> String.replace(~r/^#+\s*/u, "")
    |> String.replace(~r/^(?:title|category)\s*:\s*/iu, "")
    |> String.trim(~s("'“”‘’ ))
  end

  defp conversation_ref(ctx), do: "draft/#{conversation_id(ctx) || "anonymous"}"

  defp conversation_id(%Context{state: %{conversation_id: value}}) when not is_nil(value),
    do: to_string(value)

  defp conversation_id(_ctx), do: nil
end
