defmodule ExBlog.Ecosystem do
  @moduledoc """
  Keeps the published Spectre ecosystem compatibility matrix on the home page.

  `spectre_ecosystem` rebuilds every satellite library against the current
  `spectre` commit and republishes the result as `status.json`. That job runs
  once a day, so this process refreshes the document on the same cadence — with
  the `Process.send_after/3` scheduling the Git sync already uses — and keeps
  the parsed snapshot in a public ETS table.

  Two consequences are deliberate:

    * rendering the home page reads ETS and never performs a network call, so a
      slow or unreachable GitHub Pages host cannot slow a request down;
    * a failed refresh keeps the previous snapshot on screen and retries sooner
      than the daily cadence, so an upstream outage degrades to stale data
      instead of an empty section.
  """

  use GenServer

  require Logger

  alias ExBlog.Ecosystem.Snapshot

  @table __MODULE__
  @snapshot_key :snapshot

  @default_url "https://elchemista.github.io/spectre_ecosystem/status.json"
  @default_interval_ms :timer.hours(24)
  @default_retry_interval_ms :timer.minutes(30)
  @request_timeout_ms :timer.seconds(15)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  The last successfully parsed snapshot, or `nil` before the first refresh.
  """
  @spec snapshot() :: Snapshot.t() | nil
  def snapshot do
    case :ets.whereis(@table) do
      :undefined ->
        nil

      table ->
        case :ets.lookup(table, @snapshot_key) do
          [{@snapshot_key, snapshot}] -> snapshot
          [] -> nil
        end
    end
  end

  @doc """
  Identifies the rendered matrix for the public ETag.

  Returns a stable marker while no snapshot exists, so the home page stays
  cacheable before the first refresh completes.
  """
  @spec fingerprint() :: String.t()
  def fingerprint do
    case snapshot() do
      %Snapshot{fingerprint: fingerprint} -> fingerprint
      nil -> "no-ecosystem"
    end
  end

  @doc """
  Fetches the document now instead of waiting for the next scheduled refresh.
  """
  @spec refresh(GenServer.server()) :: {:ok, Snapshot.t()} | {:error, term()}
  def refresh(server \\ __MODULE__) do
    GenServer.call(server, :refresh, @request_timeout_ms + :timer.seconds(5))
  end

  @impl GenServer
  def init(opts) do
    _table = :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])

    state = %{
      url: Keyword.get(opts, :url, config(:status_url, @default_url)),
      interval:
        Keyword.get(opts, :interval_ms, config(:refresh_interval_ms, @default_interval_ms)),
      retry_interval:
        Keyword.get(
          opts,
          :retry_interval_ms,
          config(:retry_interval_ms, @default_retry_interval_ms)
        ),
      last_result: nil
    }

    # The first refresh runs as a message, so a slow or unreachable host never
    # delays application boot.
    if Keyword.get(opts, :refresh_on_start?, true), do: send(self(), :refresh)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:refresh, _from, state) do
    result = refresh_snapshot(state)
    {:reply, result, %{state | last_result: result}}
  end

  @impl GenServer
  def handle_info(:refresh, state) do
    result = refresh_snapshot(state)

    case result do
      {:ok, _snapshot} -> schedule(state.interval)
      {:error, _reason} -> schedule(state.retry_interval)
    end

    {:noreply, %{state | last_result: result}}
  end

  defp refresh_snapshot(state) do
    with {:ok, payload} <- fetch(state.url),
         {:ok, snapshot} <- Snapshot.parse(payload) do
      true = :ets.insert(@table, {@snapshot_key, snapshot})
      {:ok, snapshot}
    else
      {:error, reason} = error ->
        Logger.warning("ecosystem status refresh failed: #{inspect(reason)}")
        error
    end
  end

  defp fetch(url) do
    options =
      [url: url, receive_timeout: @request_timeout_ms, retry: false]
      |> Keyword.merge(Application.get_env(:ex_blog, :ecosystem_req_options, []))

    case Req.get(options) do
      {:ok, %Req.Response{status: 200, body: body}} -> decode(body)
      {:ok, %Req.Response{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Req decodes a JSON content type on its own; a host serving the artifact as
  # plain text still has to parse.
  defp decode(body) when is_map(body), do: {:ok, body}

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      {:ok, _other} -> {:error, :invalid_payload}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode(_body), do: {:error, :invalid_payload}

  defp schedule(interval), do: Process.send_after(self(), :refresh, interval)

  defp config(key, default) do
    :ex_blog
    |> Application.get_env(:ecosystem, [])
    |> Keyword.get(key, default)
  end
end
