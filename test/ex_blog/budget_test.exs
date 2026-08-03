defmodule ExBlog.BudgetTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Budget
  alias ExBlog.Config

  test "records usage, converts currency, and reports aggregates" do
    now = ~U[2026-08-03 12:00:00.000000Z]

    assert {:ok, usage} =
             Budget.record(%{
               occurred_at: now,
               purpose: :translation,
               level: :deep,
               model: "provider/deep",
               prompt_tokens: 1_000,
               completion_tokens: 500,
               cost_usd: "1.50",
               subject_type: "article",
               subject_ref: "content/it/post.md"
             })

    assert Decimal.equal?(usage.cost_eur, Decimal.new("1.380"))

    status = Budget.status(now: now)
    assert status.spent_today_eur == "1.38"
    assert status.spent_month_eur == "1.38"
    assert status.by_model_eur == %{"provider/deep" => "1.38"}
    assert Decimal.equal?(Budget.subject_cost("article", "content/it/post.md"), usage.cost_eur)
  end

  test "blocks only expensive generations at monthly and article limits" do
    config =
      Config.test_config(
        monthly_budget_eur: Decimal.new("1.00"),
        max_article_cost_eur: Decimal.new("0.50")
      )

    assert :ok = Budget.authorize(:fast, config: config, estimated_cost_eur: "99")
    assert :ok = Budget.authorize(:deep, config: config, estimated_cost_eur: "0.49")

    assert {:error, :article_budget_exceeded} =
             Budget.authorize(:deep,
               config: config,
               estimated_cost_eur: "0.50",
               subject_type: "article",
               subject_ref: "one"
             )

    assert {:ok, _usage} =
             Budget.record(%{
               purpose: :article_generation,
               level: :deep,
               model: "provider/deep",
               cost_eur: "1.00"
             })

    assert {:error, :monthly_budget_exceeded} =
             Budget.authorize(:balanced, config: config)

    assert :ok = Budget.authorize(:fast, config: config)
  end
end
