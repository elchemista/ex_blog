defmodule ExBlog.Agent.Works.SyncAndVerify do
  @moduledoc """
  Precise maintenance procedure: synchronize the content checkout, then verify
  the published site with Spectre Lens.

  This Work is the showcase for combining `Spectre.Work` with the agent. The
  administrator asks for a verification in plain English, the route handler
  starts this Work on the blog's Agent Instance, and the conversation receives
  an immediate acknowledgement while the procedure continues on the shared
  operational runtime.

  The controller is a deterministic reducer over three registered operations:

    1. `:sync_repository` — the same fetch/reset/rebuild the periodic sync runs;
    2. `:collect_pages` — a bounded list of public URLs from the ETS index;
    3. `:audit_page` — one deterministic Spectre Lens audit per page.

  It performs no Git push and no model inference, so it needs no policy
  confirmation and spends no OpenRouter budget. Page results accumulate in
  controller state and in the loop's bounded result window, where the
  verification-status route reads them back.
  """

  use Spectre.Work,
    id: :sync_and_verify,
    version: 1,
    input: :map,
    state: :map,
    budget: [steps: 100, attempts: 150]

  alias ExBlog.Agent.Verification

  operation(:sync_repository, {Verification, :sync},
    input: :map,
    output: :map,
    side_effect: :idempotent,
    retry: [max_attempts: 2]
  )

  operation(:collect_pages, {Verification, :collect_pages},
    input: :map,
    output: :map,
    side_effect: :none
  )

  operation(:audit_page, {Verification, :audit_page},
    input: :map,
    output: :map,
    side_effect: :idempotent,
    retry: [max_attempts: 2]
  )

  @impl true
  def init(_input, _context) do
    {:ok, %{"phase" => "sync", "queue" => [], "pages" => [], "commit" => nil, "skipped" => 0}}
  end

  @impl true
  def next(%{"phase" => "sync"}, _context),
    do: run(:sync_repository, %{}, phase: :sync)

  def next(%{"phase" => "collect"}, _context),
    do: run(:collect_pages, %{}, phase: :collect)

  def next(%{"phase" => "audit", "queue" => [url | _rest]}, _context),
    do: run(:audit_page, %{"url" => url}, phase: :audit)

  def next(%{"phase" => "audit", "queue" => []} = state, _context),
    do: complete(report(state))

  @impl true
  def apply_result(state, %{operation: :sync_repository}, result, _context) do
    {:ok, %{state | "phase" => "collect", "commit" => result.value["commit"]}}
  end

  def apply_result(state, %{operation: :collect_pages}, result, _context) do
    {:ok,
     %{
       state
       | "phase" => "audit",
         "queue" => result.value["urls"],
         "skipped" => result.value["skipped"]
     }}
  end

  def apply_result(%{"queue" => [_url | rest]} = state, %{operation: :audit_page}, result, _ctx) do
    {:ok, %{state | "queue" => rest, "pages" => [result.value | state["pages"]]}}
  end

  @impl true
  def complete(%{"phase" => "audit", "queue" => []} = state, _context),
    do: complete(report(state))

  def complete(_state, _context), do: :continue

  defp report(state) do
    pages = Enum.reverse(state["pages"])

    %{
      "commit" => state["commit"],
      "pages" => pages,
      "healthy" => Enum.count(pages, & &1["ok"]),
      "unhealthy" => Enum.count(pages, &(not &1["ok"])),
      "skipped" => state["skipped"]
    }
  end
end
