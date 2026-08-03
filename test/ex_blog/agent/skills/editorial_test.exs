defmodule ExBlog.Agent.Skills.EditorialTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Agent
  alias Spectre.Result

  test "the nested creation flow collects fields and stages a Kinetic action" do
    conversation_id = conversation_id()

    assert {:ok, started} = ask("/create", conversation_id)
    assert started.route.label == :START_ARTICLE_CREATION
    assert started.route.scope == {:skill, :editorial}
    assert started.state.current_flow == :article_title
    assert started.state.current_scope == {:skill, :editorial}

    assert {:ok, titled} = ask("Phoenix e Spectre", conversation_id)
    assert titled.route.label == :CAPTURE_ARTICLE_TITLE
    assert titled.route.strategy == :creation_continuation
    assert titled.state.current_flow == :article_category

    assert {:ok, categorized} = ask("Elixir", conversation_id)
    assert categorized.route.label == :CAPTURE_ARTICLE_CATEGORY
    assert categorized.state.current_flow == :article_language

    assert {:ok, localized} = ask("it", conversation_id)
    assert localized.route.label == :CAPTURE_ARTICLE_LANGUAGE
    assert localized.state.current_flow == :article_brief

    assert {:ok, staged} =
             ask("Spiega flow annidati, skill e policy con esempi pratici.", conversation_id)

    assert staged.route.label == :CAPTURE_ARTICLE_BRIEF
    assert staged.state.current_flow == nil
    assert staged.state.current_scope == nil
    refute Map.has_key?(staged.state.data, :article_creation)

    effect = Result.pending_effect(staged)
    assert effect.name == :create_article
    assert effect.owner == ExBlog.Agent.Skills.Editorial
    assert effect.scope == {:skill, :editorial}
    assert effect.status == :waiting_policy
    assert effect.policy == {{:skill, :editorial}, :editorial_confirmation}

    assert effect.args == %{
             "title" => "Phoenix e Spectre",
             "category" => "Elixir",
             "lang" => "it",
             "brief" => "Spiega flow annidati, skill e policy con esempi pratici."
           }

    awaitable = Result.open_awaitable(staged)
    assert awaitable.name == {{:skill, :editorial}, :editorial_confirmation}
    assert staged.reply_text =~ "Titolo: Phoenix e Spectre"
  end

  test "an invalid language keeps the administrator inside the language flow" do
    conversation_id = conversation_id()

    assert {:ok, _started} = ask("/create", conversation_id)
    assert {:ok, _titled} = ask("Titolo", conversation_id)
    assert {:ok, _categorized} = ask("Categoria", conversation_id)
    assert {:ok, result} = ask("fr", conversation_id)

    assert result.route.label == :CAPTURE_ARTICLE_LANGUAGE
    assert result.state.current_flow == :article_language
    assert result.reply_text =~ "Valori ammessi: it, en"
  end

  test "the global cancel interrupt clears an active creation flow" do
    conversation_id = conversation_id()

    assert {:ok, _started} = ask("/create", conversation_id)
    assert {:ok, _titled} = ask("Titolo da scartare", conversation_id)
    assert {:ok, cancelled} = ask("/cancel", conversation_id)

    assert cancelled.route.label == :CANCEL_ARTICLE_CREATION
    assert cancelled.state.current_flow == nil
    assert cancelled.state.current_scope == nil
    refute Map.has_key?(cancelled.state.data, :article_creation)
    assert cancelled.reply_text =~ "annullata"
  end

  defp ask(message, conversation_id) do
    Spectre.ask(Agent, message, conversation_id: conversation_id)
  end

  defp conversation_id do
    "editorial-skill-#{System.unique_integer([:positive, :monotonic])}"
  end
end
