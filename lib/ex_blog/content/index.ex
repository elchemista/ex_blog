defmodule ExBlog.Content.Index do
  @moduledoc """
  Owns the read-optimized ETS article index.

  Rebuilds happen in a fresh table. A single persistent-term pointer swap makes
  the new snapshot visible, and readers retry if they raced with retirement of
  the previous table.
  """

  use GenServer

  require Logger

  alias ExBlog.Config
  alias ExBlog.Content.Article
  alias ExBlog.Content.Git
  alias ExBlog.Content.Parser

  @table_key {__MODULE__, :table}
  @invalid_log_limit 50

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec rebuild() :: {:ok, map()} | {:error, term()}
  def rebuild, do: GenServer.call(__MODULE__, :rebuild, :infinity)

  @spec all() :: [Article.t()]
  def all, do: read_table(&:ets.tab2list/1) |> Enum.map(&elem(&1, 1))

  @spec get(String.t(), String.t()) :: Article.t() | nil
  def get(lang, slug) do
    case read_table(&:ets.lookup(&1, {lang, slug})) do
      [{{^lang, ^slug}, article}] -> article
      [] -> nil
    end
  end

  @spec commit_hash() :: String.t() | nil
  def commit_hash do
    if Process.whereis(__MODULE__), do: GenServer.call(__MODULE__, :commit_hash), else: nil
  end

  @spec stats() :: map()
  def stats do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :stats)
    else
      %{total: 0, published: 0, drafts: 0, invalid: 0, commit: nil, rebuilt_at: nil}
    end
  end

  @impl true
  def init(opts) do
    root = Keyword.get(opts, :root, Config.repository_path())
    content_root = Keyword.get(opts, :content_root, Config.get().content_root)
    table = new_table()
    :persistent_term.put(@table_key, table)

    state = %{table: table, root: root, content_root: content_root, commit: nil, rebuilt_at: nil}

    if Keyword.get(opts, :rebuild?, true) do
      started_at = System.monotonic_time()

      case build_and_swap(state) do
        {:ok, next_state, summary} ->
          Logger.info(
            "content_index ready commit=#{summary.commit} total=#{summary.total} " <>
              "invalid=#{summary.invalid} duration_ms=#{elapsed_ms(started_at)}"
          )

          {:ok, next_state}

        {:error, reason} ->
          Logger.error(
            "content_index boot_failed reason=#{inspect(safe_reason(reason))} " <>
              "duration_ms=#{elapsed_ms(started_at)}"
          )

          {:stop, reason}
      end
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_call(:rebuild, _from, state) do
    started_at = System.monotonic_time()

    case build_and_swap(state) do
      {:ok, next_state, summary} ->
        Logger.info(
          "content_index rebuilt commit=#{summary.commit} total=#{summary.total} " <>
            "invalid=#{summary.invalid} duration_ms=#{elapsed_ms(started_at)}"
        )

        {:reply, {:ok, summary}, next_state}

      {:error, reason} ->
        Logger.warning(
          "content_index rebuild_failed reason=#{inspect(safe_reason(reason))} " <>
            "duration_ms=#{elapsed_ms(started_at)}"
        )

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:commit_hash, _from, state), do: {:reply, state.commit, state}

  def handle_call(:stats, _from, state) do
    articles = table_values(state.table)

    summary = %{
      total: Enum.count(articles, & &1.valid?),
      published: Enum.count(articles, &Article.published?/1),
      drafts: Enum.count(articles, &(&1.valid? and &1.status == :draft)),
      invalid: Enum.count(articles, &(not &1.valid?)),
      commit: state.commit,
      rebuilt_at: state.rebuilt_at
    }

    {:reply, summary, state}
  end

  defp build_and_swap(state) do
    table = new_table()
    pattern = Path.join([state.root, state.content_root, "**", "*.md"])

    articles =
      pattern
      |> Path.wildcard()
      |> Task.async_stream(&Parser.parse_file(&1, root: state.root), timeout: :infinity)
      |> Enum.map(fn
        {:ok, {:ok, article}} -> article
        {:ok, {:error, reason, path}} -> Article.invalid(path, reason)
        {:exit, reason} -> Article.invalid("parser-task", {:task_exit, reason})
      end)
      |> invalidate_duplicate_keys()

    log_invalid_articles(articles)

    true = :ets.insert(table, Enum.map(articles, &{Article.key(&1), &1}))

    commit =
      case Git.current_commit(path: state.root) do
        {:ok, sha} -> sha
        {:error, _reason} -> nil
      end

    old_table = state.table
    :persistent_term.put(@table_key, table)
    :ets.delete(old_table)

    rebuilt_at = DateTime.utc_now()

    summary = %{
      total: Enum.count(articles, & &1.valid?),
      invalid: Enum.count(articles, &(not &1.valid?)),
      commit: commit,
      rebuilt_at: rebuilt_at
    }

    {:ok, %{state | table: table, commit: commit, rebuilt_at: rebuilt_at}, summary}
  rescue
    error -> {:error, {:index_rebuild_failed, Exception.message(error)}}
  end

  defp read_table(fun, attempts \\ 2)

  defp read_table(_fun, 0), do: []

  defp read_table(fun, attempts) do
    table = :persistent_term.get(@table_key, nil)

    if is_reference(table) do
      fun.(table)
    else
      []
    end
  rescue
    ArgumentError -> read_table(fun, attempts - 1)
  end

  defp table_values(table), do: :ets.tab2list(table) |> Enum.map(&elem(&1, 1))

  defp new_table do
    :ets.new(__MODULE__, [:set, :protected, read_concurrency: true])
  end

  defp invalidate_duplicate_keys(articles) do
    duplicate_keys =
      articles
      |> Enum.filter(& &1.valid?)
      |> Enum.group_by(&Article.key/1)
      |> Enum.flat_map(fn
        {_key, [_article]} -> []
        {key, _articles} -> [key]
      end)
      |> MapSet.new()

    Enum.map(articles, fn article ->
      if article.valid? and MapSet.member?(duplicate_keys, Article.key(article)) do
        Article.invalid(article.path, {:duplicate_article, article.lang, article.slug})
      else
        article
      end
    end)
  end

  defp log_invalid_articles(articles) do
    invalid = Enum.reject(articles, & &1.valid?)

    invalid
    |> Enum.take(@invalid_log_limit)
    |> Enum.each(fn article ->
      Logger.warning(
        "content_index article_invalid path=#{inspect(Config.redact(article.path))} " <>
          "errors=#{inspect(safe_reason(article.errors))}"
      )
    end)

    if length(invalid) > @invalid_log_limit do
      Logger.warning(
        "content_index invalid_log_truncated omitted=#{length(invalid) - @invalid_log_limit}"
      )
    end
  end

  defp safe_reason(reason) do
    reason
    |> inspect(limit: 20, printable_limit: 1_000)
    |> Config.redact()
  end

  defp elapsed_ms(started_at) do
    started_at
    |> then(&(System.monotonic_time() - &1))
    |> System.convert_time_unit(:native, :millisecond)
  end
end
