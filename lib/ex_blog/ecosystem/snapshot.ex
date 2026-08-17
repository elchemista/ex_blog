defmodule ExBlog.Ecosystem.Snapshot do
  @moduledoc """
  Normalized view of the compatibility report published by `spectre_ecosystem`.

  The report is a public artifact rebuilt by a scheduled GitHub Actions run, so
  it is untrusted input for this site: parsing keeps only the fields the page
  renders, maps every status through a closed list instead of
  `String.to_atom/1`, accepts a link only when it is an `http(s)` URL, and drops
  entries without a usable name.

  Counters are recomputed from the parsed entries rather than copied from the
  document's own `summary`, so the numbers on the page always describe the rows
  next to them.
  """

  @enforce_keys [:libraries, :summary, :status, :fingerprint, :fetched_at]
  defstruct [:generated_at, :fetched_at, :fingerprint, :status, libraries: [], summary: %{}]

  @type library :: %{
          name: String.t(),
          status: status(),
          version: String.t() | nil,
          source: :hex | :github | :unknown,
          repository_url: String.t() | nil,
          version_url: String.t() | nil,
          run_url: String.t() | nil
        }

  @type status ::
          :passing
          | :failing
          | :pending
          | :stale
          | :not_configured
          | :not_run
          | :unknown

  @type t :: %__MODULE__{
          generated_at: DateTime.t() | nil,
          fetched_at: DateTime.t(),
          fingerprint: String.t(),
          status: status(),
          libraries: [library()],
          summary: %{
            total: non_neg_integer(),
            passing: non_neg_integer(),
            failing: non_neg_integer()
          }
        }

  # The vocabulary the publisher emits. Anything outside it renders as unknown
  # instead of inventing an atom from remote input.
  @statuses %{
    "passing" => :passing,
    "failing" => :failing,
    "pending" => :pending,
    "stale" => :stale,
    "not_configured" => :not_configured,
    "not_run" => :not_run,
    "unknown" => :unknown
  }

  # The core runtime leads the table; every satellite follows alphabetically.
  @core_library "spectre"

  @max_name_length 64
  @max_version_length 32

  @doc """
  Builds a snapshot from the decoded `status.json` document.

  Returns `{:error, :invalid_payload}` when the document carries no usable
  library entry, so a truncated or replaced artifact never blanks the page: the
  caller keeps the previous snapshot instead.
  """
  @spec parse(map(), DateTime.t()) :: {:ok, t()} | {:error, :invalid_payload}
  def parse(payload, fetched_at \\ DateTime.utc_now())

  def parse(%{"libraries" => entries} = payload, fetched_at) when is_list(entries) do
    libraries =
      entries
      |> Enum.flat_map(&parse_library/1)
      |> Enum.sort_by(&{&1.name != @core_library, &1.name})

    if libraries == [] do
      {:error, :invalid_payload}
    else
      summary = summarize(libraries)

      snapshot = %__MODULE__{
        generated_at: parse_timestamp(Map.get(payload, "generated_at")),
        fetched_at: fetched_at,
        libraries: libraries,
        summary: summary,
        status: overall_status(summary),
        fingerprint: fingerprint(libraries)
      }

      {:ok, snapshot}
    end
  end

  def parse(_payload, _fetched_at), do: {:error, :invalid_payload}

  defp parse_library(%{"name" => name} = entry) when is_binary(name) do
    case sanitize_text(name, @max_name_length) do
      nil ->
        []

      name ->
        [
          %{
            name: name,
            status: parse_status(Map.get(entry, "status")),
            version: sanitize_text(Map.get(entry, "version"), @max_version_length),
            source: parse_source(Map.get(entry, "version_source")),
            repository_url: parse_url(Map.get(entry, "repository_url")),
            version_url: parse_url(Map.get(entry, "version_url")),
            run_url: entry |> Map.get("check", %{}) |> check_run_url()
          }
        ]
    end
  end

  defp parse_library(_entry), do: []

  defp check_run_url(%{"run_url" => url}), do: parse_url(url)
  defp check_run_url(_check), do: nil

  defp parse_status(status) when is_binary(status), do: Map.get(@statuses, status, :unknown)
  defp parse_status(_status), do: :unknown

  defp parse_source("hex"), do: :hex
  defp parse_source("github"), do: :github
  defp parse_source(_source), do: :unknown

  defp parse_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) -> url
      _other -> nil
    end
  end

  defp parse_url(_url), do: nil

  defp parse_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp parse_timestamp(_value), do: nil

  defp sanitize_text(value, max_length) when is_binary(value) do
    value
    |> String.trim()
    |> String.slice(0, max_length)
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp sanitize_text(_value, _max_length), do: nil

  defp summarize(libraries) do
    %{
      total: length(libraries),
      passing: Enum.count(libraries, &(&1.status == :passing)),
      failing: Enum.count(libraries, &(&1.status == :failing))
    }
  end

  defp overall_status(%{failing: failing}) when failing > 0, do: :failing
  defp overall_status(%{total: total, passing: total}) when total > 0, do: :passing
  defp overall_status(_summary), do: :unknown

  # Identifies what the page renders, so a cached response is revalidated when —
  # and only when — the matrix itself changes. The publication timestamp is left
  # out on purpose: a rerun with identical results must not expire every ETag.
  defp fingerprint(libraries) do
    libraries
    |> Enum.map_join("|", &"#{&1.name}:#{&1.status}:#{&1.version}:#{&1.source}")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end
end
