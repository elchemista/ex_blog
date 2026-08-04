defmodule ExBlog.AI.KineticPlannerOpenRouterTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Agent.KineticPlanner

  @publish_id "Elixir.ExBlog.Agent.KineticActions.publish_article/2"

  setup {Req.Test, :verify_on_exit!}

  setup do
    previous_primary = Application.get_env(:ex_blog, :kinetic_planner_llm)
    previous_fallbacks = Application.get_env(:ex_blog, :kinetic_planner_llm_fallbacks)
    previous_req_options = Application.get_env(:ex_blog, :openrouter_req_options)

    on_exit(fn ->
      restore_env(:kinetic_planner_llm, previous_primary)
      restore_env(:kinetic_planner_llm_fallbacks, previous_fallbacks)
      restore_env(:openrouter_req_options, previous_req_options)
    end)

    :ok
  end

  test "the planner uses its explicit OpenRouter model and preserves prompt trust sections" do
    Application.put_env(:ex_blog, :kinetic_planner_llm,
      adapter: ExBlog.AI.OpenRouter,
      model: "  openrouter:test/kinetic-planner  "
    )

    Application.put_env(:ex_blog, :kinetic_planner_llm_fallbacks, [])

    Application.put_env(:ex_blog, :openrouter_req_options, plug: {Req.Test, __MODULE__})

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/chat/completions"

      body = conn |> Req.Test.raw_body() |> Jason.decode!()

      assert body["model"] == "test/kinetic-planner"
      assert body["stream"] == false

      assert [system_message, user_message] = body["messages"]
      assert system_message["role"] == "system"
      assert system_message["content"] =~ "constrained action planner"
      assert user_message["role"] == "user"
      assert user_message["content"] =~ ~s(<spectre-context trust="data">)
      assert user_message["content"] =~ "allowed_actions"

      Req.Test.json(conn, %{
        "id" => "planner-generation",
        "model" => "test/kinetic-planner",
        "choices" => [
          %{
            "message" => %{
              "content" =>
                Jason.encode!(%{
                  "selected_tool" => @publish_id,
                  "args" => %{"lang" => "it", "slug" => "spectre"}
                })
            }
          }
        ],
        "usage" => %{
          "prompt_tokens" => 100,
          "completion_tokens" => 20,
          "total_tokens" => 120,
          "cost" => 0
        }
      })
    end)

    unique = System.unique_integer([:positive, :monotonic])

    opts = [
      action_providers: Spectre.ActionConfig.providers(ExBlog.Agent),
      registry_json: "/tmp/ex-blog-openrouter-missing-#{unique}.json",
      compiled_registry: "/tmp/ex-blog-openrouter-missing-#{unique}.etf",
      top_k: 1
    ]

    assert {:ok, action} = KineticPlanner.plan("PUBLISH THE ARTICLE", %{}, opts)
    assert action.name == :publish_article
    assert action.args == %{"lang" => "it", "slug" => "spectre"}
  end

  test "the OpenRouter health check includes the complete Kinetic model chain" do
    Application.put_env(:ex_blog, :kinetic_planner_llm,
      adapter: ExBlog.AI.OpenRouter,
      model: "openrouter:qwen/qwen3-next-80b-a3b-instruct"
    )

    Application.put_env(:ex_blog, :kinetic_planner_llm_fallbacks, [
      [
        adapter: ExBlog.AI.OpenRouter,
        model: "openrouter:google/gemini-2.5-flash-lite"
      ]
    ])

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/models"

      Req.Test.json(conn, %{
        "data" =>
          Enum.map(
            [
              "test/fast",
              "test/balanced",
              "test/deep",
              "test/classifier",
              "qwen/qwen3-next-80b-a3b-instruct"
            ],
            &%{"id" => &1}
          )
      })
    end)

    assert {:ok, %{models_available: false}} =
             ExBlog.AI.health(
               url: "https://openrouter.test/api/v1/models",
               req_options: [plug: {Req.Test, __MODULE__}]
             )
  end

  defp restore_env(key, nil), do: Application.delete_env(:ex_blog, key)
  defp restore_env(key, value), do: Application.put_env(:ex_blog, key, value)
end
