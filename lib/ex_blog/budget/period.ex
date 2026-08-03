defmodule ExBlog.Budget.Period do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:period, :string, autogenerate: false}
  schema "budget_periods" do
    field :spent_eur, :decimal, default: Decimal.new(0)
    field :updated_at, :utc_datetime_usec
  end
end
