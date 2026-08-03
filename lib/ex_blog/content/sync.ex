defmodule ExBlog.Content.Sync do
  @moduledoc false

  use GenServer

  alias ExBlog.Config
  alias ExBlog.Content.Git
  alias ExBlog.Content.Index

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec sync_now() :: {:ok, map()} | {:error, term()}
  def sync_now, do: GenServer.call(__MODULE__, :sync, :infinity)

  @impl true
  def init(_opts) do
    interval = Config.get().git_sync_interval_ms
    schedule(interval)
    {:ok, %{interval: interval, last_result: nil}}
  end

  @impl true
  def handle_call(:sync, _from, state) do
    result = sync()
    {:reply, result, %{state | last_result: result}}
  end

  @impl true
  def handle_info(:sync, state) do
    result = sync()
    schedule(state.interval)
    {:noreply, %{state | last_result: result}}
  end

  defp sync do
    with {:ok, commit} <- Git.sync(),
         {:ok, summary} <- Index.rebuild() do
      {:ok, Map.put(summary, :commit, commit)}
    end
  end

  defp schedule(interval), do: Process.send_after(self(), :sync, interval)
end
