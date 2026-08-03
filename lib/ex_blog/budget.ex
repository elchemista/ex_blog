defmodule ExBlog.Budget do
  @moduledoc """
  Runtime LLM cost ledger and pre-flight guard.

  Budget values are configured in EUR. OpenRouter costs are recorded in USD
  and converted with the deployment's explicit approximation rate.
  """

  import Ecto.Query

  alias ExBlog.Budget.Period
  alias ExBlog.Budget.Usage
  alias ExBlog.Config
  alias ExBlog.Repo

  @expensive_levels [:balanced, :deep]

  @spec authorize(atom(), keyword()) :: :ok | {:error, term()}
  def authorize(level, opts \\ []) do
    if level in @expensive_levels do
      config = Keyword.get(opts, :config, Config.get())
      estimate = decimal(Keyword.get(opts, :estimated_cost_eur, 0))
      monthly_spent = monthly_spent()
      projected_monthly = Decimal.add(monthly_spent, estimate)

      cond do
        Decimal.compare(projected_monthly, config.monthly_budget_eur) in [:eq, :gt] ->
          {:error, :monthly_budget_exceeded}

        article_limit_exceeded?(opts, estimate, config) ->
          {:error, :article_budget_exceeded}

        true ->
          :ok
      end
    else
      :ok
    end
  end

  @spec record(map(), keyword()) :: {:ok, Usage.t()} | {:error, term()}
  def record(attrs, opts \\ []) when is_map(attrs) do
    config = Keyword.get(opts, :config, Config.get())
    cost_usd = decimal(Map.get(attrs, :cost_usd, Map.get(attrs, "cost_usd", 0)))
    cost_eur = decimal(Map.get(attrs, :cost_eur, Decimal.mult(cost_usd, config.usd_eur_rate)))
    occurred_at = Map.get(attrs, :occurred_at, DateTime.utc_now())

    usage_attrs = %{
      occurred_at: occurred_at,
      purpose: string_value(attrs, :purpose, "unspecified"),
      level: string_value(attrs, :level, "unknown"),
      model: string_value(attrs, :model, "unknown"),
      prompt_tokens: integer_value(attrs, :prompt_tokens),
      completion_tokens: integer_value(attrs, :completion_tokens),
      cost_usd: cost_usd,
      cost_eur: cost_eur,
      subject_type: optional_string(attrs, :subject_type),
      subject_ref: optional_string(attrs, :subject_ref),
      conversation_id: optional_string(attrs, :conversation_id)
    }

    Repo.transaction(fn ->
      usage =
        %Usage{}
        |> Usage.changeset(usage_attrs)
        |> Repo.insert!()

      period = period(occurred_at)
      now = DateTime.utc_now()

      {_count, _rows} =
        Repo.insert_all(
          Period,
          [%{period: period, spent_eur: cost_eur, updated_at: now}],
          conflict_target: [:period],
          on_conflict: [inc: [spent_eur: cost_eur], set: [updated_at: now]]
        )

      usage
    end)
  end

  @spec status(keyword()) :: map()
  def status(opts \\ []) do
    config = Keyword.get(opts, :config, Config.get())
    now = Keyword.get(opts, :now, DateTime.utc_now())
    usages = usages_for_month(now)
    spent = sum_cost(usages)
    today = DateTime.to_date(now)

    spent_today =
      usages
      |> Enum.filter(&(DateTime.to_date(&1.occurred_at) == today))
      |> sum_cost()

    by_model =
      usages
      |> Enum.group_by(& &1.model)
      |> Map.new(fn {model, rows} -> {model, Decimal.to_string(sum_cost(rows))} end)

    %{
      period: period(now),
      spent_today_eur: Decimal.to_string(spent_today),
      spent_month_eur: Decimal.to_string(spent),
      monthly_budget_eur: Decimal.to_string(config.monthly_budget_eur),
      remaining_eur:
        config.monthly_budget_eur
        |> Decimal.sub(spent)
        |> Decimal.max(Decimal.new(0))
        |> Decimal.to_string(),
      by_model_eur: by_model
    }
  end

  @spec subject_cost(String.t(), String.t()) :: Decimal.t()
  def subject_cost(type, reference) do
    Usage
    |> where([usage], usage.subject_type == ^type and usage.subject_ref == ^reference)
    |> Repo.all()
    |> sum_cost()
  end

  @spec monthly_spent(DateTime.t()) :: Decimal.t()
  def monthly_spent(now \\ DateTime.utc_now()) do
    case Repo.get(Period, period(now)) do
      %Period{spent_eur: spent} -> spent
      nil -> Decimal.new(0)
    end
  end

  defp article_limit_exceeded?(opts, estimate, config) do
    case {Keyword.get(opts, :subject_type), Keyword.get(opts, :subject_ref)} do
      {type, reference} when is_binary(type) and is_binary(reference) ->
        projected = Decimal.add(subject_cost(type, reference), estimate)
        Decimal.compare(projected, config.max_article_cost_eur) in [:eq, :gt]

      _other ->
        false
    end
  end

  defp usages_for_month(now) do
    first = Date.beginning_of_month(DateTime.to_date(now))
    next = first |> Date.end_of_month() |> Date.add(1)
    {:ok, first_at} = DateTime.new(first, ~T[00:00:00], "Etc/UTC")
    {:ok, next_at} = DateTime.new(next, ~T[00:00:00], "Etc/UTC")

    Usage
    |> where([usage], usage.occurred_at >= ^first_at and usage.occurred_at < ^next_at)
    |> Repo.all()
  end

  defp sum_cost(rows),
    do: Enum.reduce(rows, Decimal.new(0), &Decimal.add(&1.cost_eur, &2))

  defp period(%DateTime{} = datetime) do
    date = DateTime.to_date(datetime)
    "#{date.year}-#{date.month |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp decimal(%Decimal{} = value), do: value
  defp decimal(value) when is_integer(value), do: Decimal.new(value)
  defp decimal(value) when is_float(value), do: value |> Float.to_string() |> Decimal.new()

  defp decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _other -> Decimal.new(0)
    end
  end

  defp decimal(_value), do: Decimal.new(0)

  defp integer_value(attrs, key) do
    case Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), 0)) do
      value when is_integer(value) and value >= 0 -> value
      _other -> 0
    end
  end

  defp string_value(attrs, key, default), do: optional_string(attrs, key) || default

  defp optional_string(attrs, key) do
    case Map.get(attrs, key, Map.get(attrs, Atom.to_string(key))) do
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) -> value
      _other -> nil
    end
  end
end
