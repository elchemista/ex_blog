defmodule ExBlog.Budget.Usage do
  @moduledoc "Durable AI usage entry stored by `ExBlog.Storage`."

  @enforce_keys [
    :occurred_at,
    :purpose,
    :level,
    :model,
    :prompt_tokens,
    :completion_tokens,
    :cost_usd,
    :cost_eur
  ]

  defstruct [
    :occurred_at,
    :purpose,
    :level,
    :model,
    :cost_usd,
    :cost_eur,
    :subject_type,
    :subject_ref,
    :conversation_id,
    prompt_tokens: 0,
    completion_tokens: 0
  ]

  @type t :: %__MODULE__{
          occurred_at: DateTime.t(),
          purpose: String.t(),
          level: String.t(),
          model: String.t(),
          prompt_tokens: non_neg_integer(),
          completion_tokens: non_neg_integer(),
          cost_usd: Decimal.t(),
          cost_eur: Decimal.t(),
          subject_type: String.t() | nil,
          subject_ref: String.t() | nil,
          conversation_id: String.t() | nil
        }
end
