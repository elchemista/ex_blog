defmodule ExBlog.Agent.Verification do
  @moduledoc """
  Operation executors for the sync-and-verify Work.

  Each public function is a registered `Spectre.Work` operation executor: it
  receives a portable input map, performs one bounded step, and returns
  portable data. All slow I/O lives here so the Work controller remains a
  deterministic reducer.

  Audits reuse `ExBlog.Agent.PageAudit` with a deterministic assessor: the
  Work verifies pages with Lens' machine-observable checks only, so a full
  site verification never spends OpenRouter budget.
  """

  alias ExBlog.Agent.PageAudit
  alias ExBlog.Config
  alias ExBlog.Content

  @max_pages 16
  @max_issues 5

  @doc "Fetches the canonical branch and rebuilds ETS, like the periodic sync."
  @spec sync(map(), term()) :: {:ok, map()} | {:error, term()}
  def sync(_input, _context) do
    case sync_adapter().sync_now() do
      {:ok, summary} -> {:ok, %{"commit" => commit(summary)}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Collects the bounded list of public page URLs to verify."
  @spec collect_pages(map(), term()) :: {:ok, map()}
  def collect_pages(_input, _context) do
    base = Config.canonical_url()

    article_urls =
      Content.list(lang: :all, status: :published)
      |> Enum.map(&"#{base}/#{&1.lang}/#{&1.slug}")

    total = 1 + length(article_urls)
    urls = Enum.take([base | article_urls], @max_pages)

    {:ok, %{"urls" => urls, "total" => total, "skipped" => total - length(urls)}}
  end

  @doc "Runs the deterministic Lens audit for one URL and reports its health."
  @spec audit_page(map(), term()) :: {:ok, map()}
  def audit_page(%{"url" => url}, _context) do
    case audit_adapter().check(url, assessor: &deterministic_assessment/1) do
      {:ok, result} ->
        {:ok,
         %{
           "url" => result.url,
           "ok" => result.baseline_ok?,
           "issues" => Enum.take(result.issues, @max_issues)
         }}

      {:error, reason} ->
        # One unreachable page must not abort the whole verification; the
        # page is reported as unhealthy instead.
        {:ok,
         %{"url" => url, "ok" => false, "issues" => ["audit failed: #{safe_reason(reason)}"]}}
    end
  end

  @doc "Static assessment used instead of a model call during Work audits."
  @spec deterministic_assessment(String.t()) :: {:ok, String.t()}
  def deterministic_assessment(_prompt) do
    {:ok, "Deterministic checks only; no model assessment was requested."}
  end

  defp commit(%{commit: commit}) when is_binary(commit), do: commit
  defp commit(_summary), do: nil

  defp safe_reason(reason), do: inspect(reason, limit: 10, printable_limit: 200)

  defp sync_adapter,
    do: Application.get_env(:ex_blog, :verification_sync, ExBlog.Content.Sync)

  defp audit_adapter,
    do: Application.get_env(:ex_blog, :verification_page_audit, PageAudit)
end
