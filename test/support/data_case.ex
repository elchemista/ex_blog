defmodule ExBlog.DataCase do
  @moduledoc """
  Test case for code that talks to the ExBlog SQLite repository.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias ExBlog.Repo

  using do
    quote do
      alias ExBlog.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import ExBlog.DataCase
    end
  end

  setup tags do
    ExBlog.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    owner = Sandbox.start_owner!(Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(owner) end)
  end
end
