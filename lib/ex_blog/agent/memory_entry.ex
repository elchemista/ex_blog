defmodule ExBlog.Agent.MemoryEntry do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "spectre_memory" do
    field :agent, :string
    field :cue, :string
    field :embedding, {:array, :float}
    field :label, :string
    field :verified, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:agent, :cue, :embedding, :label, :verified])
    |> validate_required([:agent, :cue, :label, :verified])
  end
end
