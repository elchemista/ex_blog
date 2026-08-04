defmodule ExBlog.Agent.KineticPlannerTest do
  use ExUnit.Case, async: true

  alias ExBlog.Agent.KineticPlanner
  alias Spectre.Prompt.Plan

  @publish_id "Elixir.ExBlog.Agent.KineticActions.publish_article/2"

  def complete_plan(%Plan{} = plan, opts) do
    send(Keyword.fetch!(opts, :test_pid), {:planner_llm_called, plan, opts})

    case Keyword.get(opts, :failure) do
      nil -> {:ok, Keyword.fetch!(opts, :response)}
      reason -> {:error, reason}
    end
  end

  test "uses a typed, constrained LLM fallback when deterministic planning fails" do
    response = planner_response(@publish_id, %{"lang" => "it", "slug" => "spectre"})

    assert {:ok, action} =
             KineticPlanner.plan(
               ~s(PUBLISH ARTICLE LANG="it" SLUG="spectre"),
               %{},
               planner_opts(response)
             )

    assert action.name == :publish_article
    assert action.via == :local
    assert action.args == %{"lang" => "it", "slug" => "spectre"}
    assert action.planned_by == KineticPlanner
    assert action.metadata.fallback == :llm
    assert action.metadata.selected_tool == @publish_id

    assert_receive {:planner_llm_called, %Plan{} = plan, llm_opts}
    sections = Plan.sections(plan)

    assert Enum.any?(
             sections.instructions,
             &String.contains?(&1.content, "constrained action planner")
           )

    assert Enum.all?(sections.context, &(&1.trust == :data))

    payload = sections.context |> Enum.map_join("\n", & &1.content) |> Jason.decode!()
    assert payload["instruction"] == ~s(PUBLISH ARTICLE LANG="it" SLUG="spectre")
    assert Enum.any?(payload["allowed_actions"], &(&1["id"] == @publish_id))
    assert llm_opts[:purpose] == :kinetic_planner
    assert llm_opts[:temperature] == 0.0
    assert llm_opts[:model] == "test/planner"
  end

  test "preserves visible reply text and uses the original request for malformed AL" do
    response = planner_response(@publish_id, %{"lang" => "en", "slug" => "spectre"})
    ctx = %{input: Spectre.Input.new("publish the English Spectre article")}

    assert {:ok, %{reply_text: "I will check it.", actions: [action]}} =
             KineticPlanner.plan_response(
               ~s(I will check it.\n<al>{"tool":"publish"}</al>),
               ctx,
               planner_opts(response)
             )

    assert action.name == :publish_article
    assert action.args == %{"lang" => "en", "slug" => "spectre"}

    assert_receive {:planner_llm_called, plan, _opts}
    payload = plan |> Plan.sections() |> Map.fetch!(:context) |> context_payload()

    assert payload["instruction"] == "publish the English Spectre article"
    assert payload["user_request"] == "publish the English Spectre article"
    assert payload["model_action_candidate"] == ~s({"tool":"publish"})
    assert payload["parser_error"] == "invalid_al_verb"
  end

  test "rejects tools and arguments outside the mounted Kinetic catalog" do
    hallucinated = planner_response("System.erase/0", %{})

    assert {:error, {:kinetic_planner_action_not_allowed, "System.erase/0"}} =
             KineticPlanner.plan("ERASE EVERYTHING", %{}, planner_opts(hallucinated))

    missing = planner_response(@publish_id, %{"lang" => "it"})

    assert {:error, {:missing_kinetic_planner_action_args, ["slug"]}} =
             KineticPlanner.plan("PUBLISH THE ARTICLE", %{}, planner_opts(missing))
  end

  test "fails over to a different planner model after provider failure" do
    response = planner_response(@publish_id, %{"lang" => "it", "slug" => "spectre"})

    opts =
      response
      |> planner_opts()
      |> Keyword.put(:llm_fallback,
        adapter: __MODULE__,
        model: "primary/planner",
        test_pid: self(),
        response: response,
        failure: :rate_limited
      )
      |> Keyword.put(:llm_fallbacks, [
        [
          adapter: __MODULE__,
          model: "fallback/planner",
          test_pid: self(),
          response: response
        ]
      ])

    assert {:ok, action} = KineticPlanner.plan("PUBLISH THE ARTICLE", %{}, opts)
    assert action.name == :publish_article

    assert_receive {:planner_llm_called, _plan, primary_opts}
    assert primary_opts[:model] == "primary/planner"

    assert_receive {:planner_llm_called, _plan, fallback_opts}
    assert fallback_opts[:model] == "fallback/planner"
  end

  test "fails over when the primary model returns an invalid decision" do
    invalid = planner_response("System.erase/0", %{})
    valid = planner_response(@publish_id, %{"lang" => "it", "slug" => "spectre"})

    opts =
      invalid
      |> planner_opts()
      |> Keyword.put(:llm_fallback,
        adapter: __MODULE__,
        model: "invalid/planner",
        test_pid: self(),
        response: invalid
      )
      |> Keyword.put(:llm_fallbacks, [
        [
          adapter: __MODULE__,
          model: "valid/planner",
          test_pid: self(),
          response: valid
        ]
      ])

    assert {:ok, action} = KineticPlanner.plan("PUBLISH THE ARTICLE", %{}, opts)
    assert action.name == :publish_article
    assert_receive {:planner_llm_called, _plan, invalid_opts}
    assert invalid_opts[:model] == "invalid/planner"
    assert_receive {:planner_llm_called, _plan, valid_opts}
    assert valid_opts[:model] == "valid/planner"
  end

  test "rejects a malformed planner configuration without invoking it" do
    opts =
      planner_response(@publish_id, %{})
      |> planner_opts()
      |> Keyword.put(:llm_fallback, [:not_a_keyword_entry])

    assert {:error, :invalid_kinetic_planner_llm_config} =
             KineticPlanner.plan("NOT A VALID ACTION", %{}, opts)

    refute_receive {:planner_llm_called, _plan, _opts}
  end

  test "keeps deterministic Kinetic as the primary planner" do
    response = planner_response(@publish_id, %{"lang" => "it", "slug" => "unused"})

    opts =
      response
      |> planner_opts()
      |> Keyword.delete(:registry_json)
      |> Keyword.delete(:compiled_registry)

    assert {:ok, action} =
             KineticPlanner.plan(
               ~s(PUBLISH ARTICLE LANG="it" SLUG="spectre"),
               %{},
               opts
             )

    assert action.name == :publish_article
    assert action.args == %{"lang" => "it", "slug" => "spectre"}
    refute_receive {:planner_llm_called, _plan, _opts}
  end

  test "the Stack installs the deterministic-first fallback planner" do
    assert {KineticPlanner, opts} = Spectre.ActionConfig.planner(ExBlog.Agent)
    assert opts[:top_k] == 1
    assert opts[:tool_threshold] == 0.0
    assert opts[:mapping_threshold] == 0.0
  end

  defp planner_opts(response) do
    unique = System.unique_integer([:positive, :monotonic])

    [
      action_providers: Spectre.ActionConfig.providers(ExBlog.Agent),
      registry_json: "/tmp/ex-blog-missing-registry-#{unique}.json",
      compiled_registry: "/tmp/ex-blog-missing-registry-#{unique}.etf",
      top_k: 1,
      llm_fallback: [
        adapter: __MODULE__,
        model: "test/planner",
        test_pid: self(),
        response: response
      ]
    ]
  end

  defp planner_response(selected_tool, args) do
    Jason.encode!(%{"selected_tool" => selected_tool, "args" => args})
  end

  defp context_payload(fragments) do
    fragments
    |> Enum.map_join("\n", & &1.content)
    |> Jason.decode!()
  end
end
