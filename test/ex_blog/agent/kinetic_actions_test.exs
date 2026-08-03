defmodule ExBlog.Agent.KineticActionsTest do
  use ExUnit.Case, async: false

  alias ExBlog.Agent
  alias ExBlog.Agent.KineticActions
  alias ExBlog.Agent.Skills.Editorial
  alias Spectre.ActionConfig
  alias Spectre.ActionPlanner
  alias Spectre.ActionProtection
  alias Spectre.Context
  alias Spectre.Effect
  alias Spectre.Input
  alias Spectre.State
  alias SpectreKinetic.Tool.Extractor

  test "extracts typed article and Git operations from @al annotations" do
    assert {:ok, actions} = Extractor.extract_module(KineticActions)

    assert Enum.map(actions, & &1["name"]) == [
             "list_articles",
             "read_article",
             "search_articles",
             "show_config",
             "openrouter_status",
             "budget_status",
             "check_page",
             "create_article",
             "revise_article",
             "translate_article",
             "generate_seo",
             "publish_article",
             "unpublish_article",
             "delete_article",
             "sync_repository"
           ]

    publish = Enum.find(actions, &(&1["name"] == "publish_article"))
    create = Enum.find(actions, &(&1["name"] == "create_article"))

    assert Enum.map(create["args"], & &1["name"]) == [
             "title",
             "lang",
             "category",
             "brief",
             "generate_seo",
             "cover",
             "cover_alt"
           ]

    assert Enum.find(create["args"], &(&1["name"] == "generate_seo"))["type"] ==
             "boolean()"

    assert Enum.map(publish["args"], &{&1["name"], &1["type"]}) == [
             {"lang", "String.t()"},
             {"slug", "String.t()"}
           ]

    assert ~s(PUBLISH ARTICLE LANG="it" SLUG="phoenix-liveview") in publish["examples"]
  end

  test "Kinetic plans a typed provider action and Spectre keeps its policy" do
    context = %Context{
      agent: Agent,
      input: Input.new("pubblica it phoenix-liveview"),
      state: %State{}
    }

    planner_opts =
      ActionConfig.planner_opts(context,
        effect_owner: Editorial,
        effect_scope: {:skill, :editorial}
      )

    assert {:ok,
            %Effect{
              name: :publish_article,
              mode: :write,
              args: %{"lang" => "it", "slug" => "phoenix-liveview"}
            } = effect} =
             ActionPlanner.plan(
               ~s(PUBLISH ARTICLE LANG="it" SLUG="phoenix-liveview"),
               context,
               planner_opts
             )

    assert Effect.via(effect) == :local

    assert ActionProtection.protected_by(Agent, effect) ==
             {{:skill, :editorial}, :editorial_confirmation}
  end

  test "builds escaped Action Language that Kinetic maps back to typed arguments" do
    title = ~s(Phoenix "senza sorprese")
    brief = "Prima riga\nSeconda riga con \\ percorso"

    command =
      KineticActions.create_article_command(
        title,
        "it",
        "Elixir",
        brief,
        true,
        "/images/articles/cover.jpg",
        "Schema del flusso"
      )

    context = %Context{
      agent: Agent,
      input: Input.new(brief),
      state: %State{}
    }

    planner_opts =
      ActionConfig.planner_opts(context,
        effect_owner: Editorial,
        effect_scope: {:skill, :editorial}
      )

    assert command =~ ~S(TITLE="Phoenix \"senza sorprese\"")

    assert {:ok, effect} = ActionPlanner.plan(command, context, planner_opts)

    assert effect.args == %{
             "title" => title,
             "lang" => "it",
             "category" => "Elixir",
             "brief" => "Prima riga Seconda riga con \\ percorso",
             "generate_seo" => true,
             "cover" => "/images/articles/cover.jpg",
             "cover_alt" => "Schema del flusso"
           }
  end

  test "the Stack installs Kinetic over the context-aware local provider" do
    assert {Spectre.Kinetic.Planner, opts} = ActionConfig.planner(Agent)
    assert opts[:top_k] == 1

    provider = Enum.find(ActionConfig.providers(Agent), &(&1.id == :local))

    assert provider.id == :local
    assert provider.module == ExBlog.Agent.Actions.Provider
  end
end
