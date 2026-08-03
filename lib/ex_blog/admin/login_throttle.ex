defmodule ExBlog.Admin.LoginThrottle do
  @moduledoc """
  Keeps a short, in-memory failure window for administrator login attempts.

  The state deliberately resets on application restart. It contains only
  opaque requester keys and monotonic timestamps, never submitted passwords.
  """

  use GenServer

  @max_attempts 5
  @window_ms :timer.minutes(15)

  @type key :: term()
  @type state :: %{optional(key()) => [integer()]}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec allow_attempt(key(), GenServer.server()) :: :ok | {:error, pos_integer()}
  def allow_attempt(key, server \\ __MODULE__) do
    GenServer.call(server, {:allow_attempt, key})
  end

  @spec reset(key(), GenServer.server()) :: :ok
  def reset(key, server \\ __MODULE__) do
    GenServer.call(server, {:reset, key})
  end

  @impl GenServer
  def init(state) do
    schedule_sweep()
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:allow_attempt, key}, _from, state) do
    now = now_ms()
    attempts = recent_attempts(Map.get(state, key, []), now)

    case Enum.reverse(attempts) do
      [oldest | _rest] when length(attempts) >= @max_attempts ->
        retry_after = max(div(@window_ms - (now - oldest), 1_000) + 1, 1)
        {:reply, {:error, retry_after}, put_attempts(state, key, attempts)}

      _available ->
        {:reply, :ok, Map.put(state, key, [now | attempts])}
    end
  end

  def handle_call({:reset, key}, _from, state) do
    {:reply, :ok, Map.delete(state, key)}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    now = now_ms()

    state =
      Enum.reduce(state, %{}, fn {key, attempts}, cleaned ->
        put_attempts(cleaned, key, recent_attempts(attempts, now))
      end)

    schedule_sweep()
    {:noreply, state}
  end

  defp recent_attempts(attempts, now) do
    Enum.filter(attempts, &(now - &1 < @window_ms))
  end

  defp put_attempts(state, key, []), do: Map.delete(state, key)
  defp put_attempts(state, key, attempts), do: Map.put(state, key, attempts)

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @window_ms)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
