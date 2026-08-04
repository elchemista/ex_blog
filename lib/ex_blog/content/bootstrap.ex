defmodule ExBlog.Content.Bootstrap do
  @moduledoc false

  use GenServer

  alias ExBlog.Content.Asset
  alias ExBlog.Content.Git

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    with {:ok, commit} <- Git.ensure_checkout(opts),
         :ok <- Asset.restore_from_repository(opts) do
      {:ok, %{commit: commit}}
    else
      {:error, reason} -> {:stop, {:content_boot_failed, reason}}
    end
  end
end
