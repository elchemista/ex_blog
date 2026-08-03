defmodule ExBlog.Agent.StateEntry do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "spectre_states" do
    field :conversation_id, :string, primary_key: true
    field :agent, :string, primary_key: true
    field :revision, :integer, default: 0
    field :payload, :map

    timestamps(type: :utc_datetime_usec)
  end
end
