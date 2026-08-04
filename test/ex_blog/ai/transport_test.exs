defmodule ExBlog.AI.TransportTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.AI.Transport
  alias ExBlog.Budget

  setup {Req.Test, :verify_on_exit!}

  test "requests usage and records a successful OpenRouter response" do
    Req.Test.expect(__MODULE__, fn conn ->
      body = conn |> Req.Test.raw_body() |> Jason.decode!()
      assert body["usage"] == %{"include" => true}

      Req.Test.json(conn, %{
        "id" => "generation-1",
        "model" => "provider/deep",
        "choices" => [%{"message" => %{"content" => "ok"}}],
        "usage" => %{
          "prompt_tokens" => 120,
          "completion_tokens" => 30,
          "cost" => 0.25
        }
      })
    end)

    assert {:ok, 200, _headers, body} =
             Transport.request(
               :post,
               "https://openrouter.test/api/v1/chat/completions",
               [{"authorization", "Bearer hidden"}],
               %{"model" => "provider/deep", "messages" => []},
               ex_blog_level: :deep,
               purpose: :article_generation,
               subject_type: "article",
               subject_ref: "content/it/example.md",
               req_options: [plug: {Req.Test, __MODULE__}]
             )

    assert body["id"] == "generation-1"
    assert Decimal.equal?(Budget.monthly_spent(), Decimal.new("0.23"))
  end

  test "budget denial happens before the HTTP boundary" do
    assert {:ok, _usage} =
             Budget.record(%{
               purpose: :test,
               level: :deep,
               model: "provider/deep",
               cost_eur: "20"
             })

    Req.Test.stub(__MODULE__, fn conn ->
      send(self(), :unexpected_http_request)
      Req.Test.json(conn, %{})
    end)

    assert {:error, :monthly_budget_exceeded} =
             Transport.request(
               :post,
               "https://openrouter.test/api/v1/chat/completions",
               [],
               %{"model" => "provider/deep"},
               ex_blog_level: :deep,
               req_options: [plug: {Req.Test, __MODULE__}]
             )

    refute_received :unexpected_http_request
  end

  test "embedding requests do not receive chat-only usage options" do
    Req.Test.expect(__MODULE__, fn conn ->
      body = conn |> Req.Test.raw_body() |> Jason.decode!()

      refute Map.has_key?(body, "usage")
      assert body["input"] == "list every article"

      Req.Test.json(conn, %{
        "model" => "perplexity/pplx-embed-v1-0.6b",
        "data" => [%{"index" => 0, "embedding" => [1.0, 0.0]}]
      })
    end)

    assert {:ok, 200, _headers, body} =
             Transport.request(
               :post,
               "https://openrouter.test/api/v1/embeddings",
               [{"authorization", "Bearer hidden"}],
               %{
                 "model" => "perplexity/pplx-embed-v1-0.6b",
                 "input" => "list every article",
                 "encoding_format" => "float"
               },
               ex_blog_level: :fast,
               purpose: :semantic_cache_embedding,
               req_options: [plug: {Req.Test, __MODULE__}]
             )

    assert [%{"embedding" => embedding}] = body["data"]
    assert embedding == [1.0, 0.0]
  end
end
