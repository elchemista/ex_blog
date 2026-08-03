defmodule ExBlog.Budget.Usage do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "llm_usage" do
    field :occurred_at, :utc_datetime_usec
    field :purpose, :string
    field :level, :string
    field :model, :string
    field :prompt_tokens, :integer, default: 0
    field :completion_tokens, :integer, default: 0
    field :cost_usd, :decimal, default: Decimal.new(0)
    field :cost_eur, :decimal, default: Decimal.new(0)
    field :subject_type, :string
    field :subject_ref, :string
    field :conversation_id, :string

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(usage, attrs) do
    usage
    |> cast(attrs, [
      :occurred_at,
      :purpose,
      :level,
      :model,
      :prompt_tokens,
      :completion_tokens,
      :cost_usd,
      :cost_eur,
      :subject_type,
      :subject_ref,
      :conversation_id
    ])
    |> validate_required([
      :occurred_at,
      :purpose,
      :level,
      :model,
      :prompt_tokens,
      :completion_tokens,
      :cost_usd,
      :cost_eur
    ])
    |> validate_number(:prompt_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:completion_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:cost_usd, greater_than_or_equal_to: 0)
    |> validate_number(:cost_eur, greater_than_or_equal_to: 0)
  end
end
