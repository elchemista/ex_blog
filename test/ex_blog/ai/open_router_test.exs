defmodule ExBlog.AI.OpenRouterTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.AI
  alias ExBlog.AI.Embedding

  setup {Req.Test, :verify_on_exit!}

  test "balanced completions use the runtime model through the budgeted Req transport" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/chat/completions"

      body = conn |> Req.Test.raw_body() |> Jason.decode!()

      assert body["model"] == "test/balanced"
      assert body["usage"] == %{"include" => true}
      assert body["provider"] == %{"sort" => "throughput"}
      assert body["messages"] == [%{"role" => "user", "content" => "Reply with OK."}]

      Req.Test.json(conn, %{
        "id" => "balanced-generation",
        "model" => "test/balanced",
        "choices" => [
          %{"finish_reason" => "stop", "message" => %{"content" => "OK"}}
        ],
        "usage" => %{
          "prompt_tokens" => 4,
          "completion_tokens" => 1,
          "total_tokens" => 5,
          "cost" => 0
        }
      })
    end)

    assert {:ok, response} =
             AI.complete(:balanced, "Reply with OK.",
               req_options: [plug: {Req.Test, __MODULE__}],
               purpose: :diagnostic,
               estimated_cost_eur: "0.001",
               subject_type: "test",
               subject_ref: "openrouter"
             )

    assert response.text == "OK"
    assert response.metadata.model == "test/balanced"
  end

  test "hosted embeddings keep application transport options outside ReqLLM validation" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/embeddings"

      body = conn |> Req.Test.raw_body() |> Jason.decode!()

      assert body["model"] == "perplexity/pplx-embed-v1-0.6b"
      assert body["input"] == "telegram diagnostic"
      assert body["dimensions"] == 1024
      refute Map.has_key?(body, "usage")

      Req.Test.json(conn, %{
        "model" => "perplexity/pplx-embed-v1-0.6b",
        "data" => [
          %{"index" => 0, "embedding" => List.duplicate(0.25, 1024)}
        ],
        "usage" => %{"prompt_tokens" => 2, "total_tokens" => 2, "cost" => 0}
      })
    end)

    assert {:ok, vector} =
             Embedding.embed("telegram diagnostic",
               req_options: [plug: {Req.Test, __MODULE__}],
               conversation_id: "openrouter-embedding-test"
             )

    assert length(vector) == 1024
  end
end
