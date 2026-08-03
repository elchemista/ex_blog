defmodule ExBlog.Content.Bootstrap do
  @moduledoc false

  use GenServer

  alias ExBlog.Content.Git

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    case Git.ensure_checkout(opts) do
      {:ok, commit} -> {:ok, %{commit: commit}}
      {:error, reason} -> {:stop, {:content_boot_failed, reason}}
    end
  end
end
