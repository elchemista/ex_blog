defmodule ExBlog.Agent.Works.SyncAndVerifyTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Agent

  defmodule FakeSync do
    @moduledoc false

    def sync_now, do: {:ok, %{commit: "abc1234", articles: 0}}
  end

  defmodule FakePageAudit do
    @moduledoc false

    # Deterministic stand-in for the Lens audit: the home page is reported
    # unhealthy so the report and status prompt exercise the issue path.
    def check(url, _opts) do
      {:ok,
       %{
         url: url,
         title: nil,
         baseline_ok?: false,
         issues: ["The document title is missing."],
         warnings: [],
         metrics: %{},
         assessment: "Deterministic checks only."
       }}
    end
  end

  defmodule VerifyClassifier do
    @moduledoc false

    def classify(_text, _opts) do
      {:ok,
       %{
         label: "VERIFY_BLOG",
         accepted?: true,
         confidence: 0.97,
         margin: 0.2,
         strategy: :local_classifier
       }}
    end
  end

  setup do
    previous_sync = Application.get_env(:ex_blog, :verification_sync)
    previous_audit = Application.get_env(:ex_blog, :verification_page_audit)
    Application.put_env(:ex_blog, :verification_sync, FakeSync)
    Application.put_env(:ex_blog, :verification_page_audit, FakePageAudit)

    on_exit(fn ->
      restore_env(:verification_sync, previous_sync)
      restore_env(:verification_page_audit, previous_audit)
    end)

    :ok
  end

  test "a natural request starts the Work, which syncs, audits, and completes" do
    instance = instance!()
    conversation_id = conversation_id()

    assert {:ok, result} =
             Spectre.ask(Agent, "Please make sure the whole published site is healthy",
               conversation_id: conversation_id,
               instance_pid: instance,
               classifier_local: VerifyClassifier
             )

    assert result.route.label == :VERIFY_BLOG
    assert result.route.scope == {:skill, :operations}
    assert result.reply_text =~ "Sync and verification started"
    assert %{operation_ref: ref} = result.metadata

    view = await_terminal(instance, ref)

    assert view.definition == :sync_and_verify
    assert view.terminal_category == :completed

    pages = Enum.filter(view.partial_results, &match?(%{"url" => _url, "ok" => _ok}, &1))
    assert [%{"ok" => false, "issues" => ["The document title is missing."]}] = pages
  end

  test "the status route reports the committed verification view" do
    instance = instance!()
    conversation_id = conversation_id()

    assert {:ok, started} =
             Spectre.ask(Agent, "Verify the whole blog for me",
               conversation_id: conversation_id,
               instance_pid: instance,
               classifier_local: VerifyClassifier
             )

    %{operation_ref: ref} = started.metadata
    _terminal = await_terminal(instance, ref)

    assert {:ok, status} =
             Spectre.ask(Agent, "How did the last site verification go",
               conversation_id: conversation_id,
               instance_pid: instance,
               semantic_learn?: false
             )

    assert status.route.label == :SHOW_VERIFICATION
    assert status.route.strategy == :semantic_cache_exact
    assert status.reply_text =~ "completed"
    assert status.reply_text =~ "healthy: 0, with issues: 1"
    assert status.reply_text =~ "The document title is missing."
  end

  test "the status route explains when no verification has run yet" do
    instance = instance!()

    assert {:ok, status} =
             Spectre.ask(Agent, "How did the last site verification go",
               conversation_id: conversation_id(),
               instance_pid: instance,
               semantic_learn?: false
             )

    assert status.route.label == :SHOW_VERIFICATION
    assert status.reply_text =~ "No sync-and-verify run is available yet"
  end

  defp instance! do
    subject = "verify-#{System.unique_integer([:positive, :monotonic])}"
    {:ok, pid} = Spectre.ensure_instance(ExBlog.SpectreSupervisor, Agent, subject)
    pid
  end

  defp await_terminal(instance, ref, remaining_ms \\ 5_000) do
    {:ok, view} = Spectre.loop(instance, ref)

    cond do
      view.status == :terminal ->
        view

      remaining_ms <= 0 ->
        flunk("sync-and-verify did not finish: #{inspect(view.status)} / #{inspect(view.phase)}")

      true ->
        Process.sleep(25)
        await_terminal(instance, ref, remaining_ms - 25)
    end
  end

  defp conversation_id do
    "sync-verify-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp restore_env(key, nil), do: Application.delete_env(:ex_blog, key)
  defp restore_env(key, value), do: Application.put_env(:ex_blog, key, value)
end
