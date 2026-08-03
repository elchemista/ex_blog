defmodule ExBlog.Content.GitOperation do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "git_operations" do
    field :op, :string
    field :commit_sha, :string
    field :files, :map, default: %{}
    field :ok, :boolean
    field :error, :string

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(operation, attrs) do
    operation
    |> cast(attrs, [:op, :commit_sha, :files, :ok, :error])
    |> validate_required([:op, :files, :ok])
  end
end
