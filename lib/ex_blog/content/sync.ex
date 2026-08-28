defmodule ExBlog.Content.Sync do
  @moduledoc false

  use GenServer

  require Logger

  alias ExBlog.Config
  alias ExBlog.Content.Asset
  alias ExBlog.Content.Git
  alias ExBlog.Content.Index

  @status_key {__MODULE__, :status}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec sync_now() :: {:ok, map()} | {:error, term()}
  def sync_now, do: GenServer.call(__MODULE__, :sync, :infinity)

  @doc "Returns the non-blocking, secret-free projection of the latest sync attempt."
  @spec status() :: map()
  def status do
    if Process.whereis(__MODULE__) do
      case :persistent_term.get(@status_key, :missing) do
        :missing -> initial_status()
        status -> status
      end
    else
      initial_status(:not_started)
    end
  end

  @impl true
  def init(opts) do
    interval = Config.get().git_sync_interval_ms
    schedule(interval)
    put_status(bootstrap_status())
    {:ok, %{interval: interval, last_result: nil, opts: opts}}
  end

  @impl true
  def handle_call(:sync, _from, state) do
    result = run_sync(:manual, state.opts)
    {:reply, result, %{state | last_result: result}}
  end

  @impl true
  def handle_info(:sync, state) do
    result = run_sync(:scheduled, state.opts)
    schedule(state.interval)
    {:noreply, %{state | last_result: result}}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    :persistent_term.erase(@status_key)
    :ok
  end

  defp run_sync(trigger, opts) do
    started_at = DateTime.utc_now()
    monotonic_started_at = System.monotonic_time()

    put_status(%{
      status: :syncing,
      trigger: trigger,
      last_started_at: started_at,
      last_finished_at: nil,
      duration_ms: nil,
      commit: Index.commit_hash(),
      total: nil,
      invalid: nil,
      error: nil
    })

    Logger.info("content_sync started trigger=#{trigger}")

    result = safe_sync(opts)
    duration_ms = elapsed_ms(monotonic_started_at)
    finished_at = DateTime.utc_now()

    log_result(result, trigger, duration_ms)
    put_status(status_from_result(result, trigger, started_at, finished_at, duration_ms))
    result
  end

  defp safe_sync(opts) do
    sync(opts)
  rescue
    exception -> {:error, {:sync_exception, Exception.message(exception)}}
  catch
    :exit, reason -> {:error, {:sync_exit, reason}}
    kind, reason -> {:error, {:sync_failure, kind, reason}}
  end

  defp sync(opts) do
    with {:ok, commit} <- Git.sync(opts),
         :ok <- Asset.restore_from_repository(opts),
         {:ok, summary} <- Index.rebuild() do
      {:ok, Map.put(summary, :commit, commit)}
    end
  end

  defp log_result({:ok, summary}, trigger, duration_ms) do
    Logger.info(
      "content_sync completed trigger=#{trigger} commit=#{Map.get(summary, :commit)} " <>
        "total=#{Map.get(summary, :total)} invalid=#{Map.get(summary, :invalid)} " <>
        "duration_ms=#{duration_ms}"
    )
  end

  defp log_result({:error, reason}, trigger, duration_ms) do
    Logger.warning(
      "content_sync failed trigger=#{trigger} code=#{error_code(reason)} " <>
        "reason=#{inspect(safe_reason(reason))} duration_ms=#{duration_ms}"
    )
  end

  defp status_from_result({:ok, summary}, trigger, started_at, finished_at, duration_ms) do
    %{
      status: :ok,
      trigger: trigger,
      last_started_at: started_at,
      last_finished_at: finished_at,
      duration_ms: duration_ms,
      commit: Map.get(summary, :commit),
      total: Map.get(summary, :total),
      invalid: Map.get(summary, :invalid),
      error: nil
    }
  end

  defp status_from_result({:error, reason}, trigger, started_at, finished_at, duration_ms) do
    %{
      status: :error,
      trigger: trigger,
      last_started_at: started_at,
      last_finished_at: finished_at,
      duration_ms: duration_ms,
      commit: Index.commit_hash(),
      total: nil,
      invalid: nil,
      error: error_code(reason)
    }
  end

  defp initial_status(status \\ :pending) do
    %{
      status: status,
      trigger: nil,
      last_started_at: nil,
      last_finished_at: nil,
      duration_ms: nil,
      commit: nil,
      total: nil,
      invalid: nil,
      error: nil
    }
  end

  defp bootstrap_status do
    stats = Index.stats()

    %{
      status: :ok,
      trigger: :bootstrap,
      last_started_at: nil,
      last_finished_at: stats.rebuilt_at,
      duration_ms: nil,
      commit: stats.commit,
      total: stats.total,
      invalid: stats.invalid,
      error: nil
    }
  end

  defp put_status(status), do: :persistent_term.put(@status_key, status)

  defp safe_reason(reason) do
    reason
    |> inspect(limit: 20, printable_limit: 1_000)
    |> Config.redact()
  end

  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp error_code(reason) when is_tuple(reason) and tuple_size(reason) > 0,
    do: reason |> elem(0) |> error_code()

  defp error_code(_reason), do: "unknown"

  defp elapsed_ms(started_at) do
    started_at
    |> then(&(System.monotonic_time() - &1))
    |> System.convert_time_unit(:native, :millisecond)
  end

  defp schedule(interval), do: Process.send_after(self(), :sync, interval)
end
