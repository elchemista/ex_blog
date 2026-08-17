defmodule ExBlog.EcosystemTest do
  # The snapshot lives in a named ETS table owned by a named process.
  use ExUnit.Case, async: false

  alias ExBlog.Ecosystem
  alias ExBlog.Ecosystem.Snapshot

  setup do
    previous = Application.get_env(:ex_blog, :ecosystem_req_options)
    Application.put_env(:ex_blog, :ecosystem_req_options, plug: {Req.Test, __MODULE__})

    on_exit(fn ->
      if previous do
        Application.put_env(:ex_blog, :ecosystem_req_options, previous)
      else
        Application.delete_env(:ex_blog, :ecosystem_req_options)
      end
    end)

    :ok
  end

  describe "refresh/1" do
    test "publishes the parsed matrix so a render only reads ETS" do
      stub_status(report())
      pid = start_ecosystem()

      assert {:ok, %Snapshot{} = refreshed} = Ecosystem.refresh(pid)
      assert %Snapshot{} = snapshot = Ecosystem.snapshot()
      assert snapshot.fingerprint == refreshed.fingerprint

      assert Enum.map(snapshot.libraries, & &1.name) == [
               "spectre",
               "spectre_lab",
               "spectre_ledger",
               "spectre_lens"
             ]

      assert snapshot.summary == %{total: 4, passing: 3, failing: 1}
      assert snapshot.status == :failing
      assert Ecosystem.fingerprint() == snapshot.fingerprint
    end

    test "keeps the last known matrix when the upstream host answers with an error" do
      stub_status(report())
      pid = start_ecosystem()
      assert {:ok, snapshot} = Ecosystem.refresh(pid)

      Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 503, "") end)

      assert {:error, {:unexpected_status, 503}} = Ecosystem.refresh(pid)
      assert Ecosystem.snapshot().fingerprint == snapshot.fingerprint
    end

    test "keeps the last known matrix when the document is unusable" do
      stub_status(report())
      pid = start_ecosystem()
      assert {:ok, snapshot} = Ecosystem.refresh(pid)

      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"libraries" => "gone"}) end)

      assert {:error, :invalid_payload} = Ecosystem.refresh(pid)
      assert Ecosystem.snapshot().fingerprint == snapshot.fingerprint
    end
  end

  describe "scheduling" do
    test "refreshes again after the configured interval" do
      test_process = self()

      Req.Test.stub(__MODULE__, fn conn ->
        send(test_process, :fetched)
        Req.Test.json(conn, report())
      end)

      pid = start_ecosystem(interval_ms: 30)

      send(pid, :refresh)

      assert_receive :fetched, 1_000
      # The scheduled follow-up proves the loop rearms itself instead of running
      # only once at boot.
      assert_receive :fetched, 1_000
    end

    test "retries sooner than the daily cadence after a failure" do
      test_process = self()

      Req.Test.stub(__MODULE__, fn conn ->
        send(test_process, :fetched)
        Plug.Conn.send_resp(conn, 500, "")
      end)

      pid = start_ecosystem(interval_ms: :timer.hours(24), retry_interval_ms: 30)

      send(pid, :refresh)

      assert_receive :fetched, 1_000
      assert_receive :fetched, 1_000
    end
  end

  describe "Snapshot.parse/2" do
    test "recomputes the counters from the entries it kept" do
      payload = %{
        "generated_at" => "2026-08-16T13:16:15.773486Z",
        "libraries" => [
          library("spectre", "passing"),
          library("spectre_lens", "failing"),
          # Nameless entries cannot be rendered or linked.
          %{"status" => "passing"},
          # A count copied from upstream would disagree with the rows shown.
          library("spectre_lab", "who-knows")
        ],
        "summary" => %{"total" => 99, "passing" => 99, "failing" => 0}
      }

      assert {:ok, snapshot} = Snapshot.parse(payload)
      assert snapshot.summary == %{total: 3, passing: 1, failing: 1}
      assert Enum.map(snapshot.libraries, & &1.status) == [:passing, :unknown, :failing]
      assert snapshot.generated_at == ~U[2026-08-16 13:16:15.773486Z]
    end

    test "drops a link that is not http(s)" do
      payload = %{
        "libraries" => [
          library("spectre", "passing")
          |> Map.put("repository_url", "javascript:alert(1)")
          |> Map.put("version_url", "https://hex.pm/packages/spectre")
        ]
      }

      assert {:ok, snapshot} = Snapshot.parse(payload)
      assert [library] = snapshot.libraries
      assert library.repository_url == nil
      assert library.version_url == "https://hex.pm/packages/spectre"
    end

    test "rejects a document without a usable entry" do
      assert {:error, :invalid_payload} = Snapshot.parse(%{"libraries" => []})
      assert {:error, :invalid_payload} = Snapshot.parse(%{})
    end

    test "changes the fingerprint only when the matrix changes" do
      payload = %{"libraries" => [library("spectre", "passing")]}
      later = %{"libraries" => [library("spectre", "failing")]}

      assert {:ok, first} = Snapshot.parse(payload, ~U[2026-08-16 00:00:00Z])
      assert {:ok, same} = Snapshot.parse(payload, ~U[2026-08-17 00:00:00Z])
      assert {:ok, changed} = Snapshot.parse(later, ~U[2026-08-17 00:00:00Z])

      assert first.fingerprint == same.fingerprint
      assert first.fingerprint != changed.fingerprint
    end
  end

  defp start_ecosystem(opts \\ []) do
    options =
      Keyword.merge([refresh_on_start?: false, url: "https://example.test/status.json"], opts)

    pid = start_supervised!({Ecosystem, options})
    :ok = Req.Test.allow(__MODULE__, self(), pid)
    pid
  end

  defp stub_status(payload) do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, payload) end)
  end

  defp report do
    %{
      "generated_at" => "2026-08-16T13:16:15.773486Z",
      "libraries" => [
        library("spectre_lens", "failing"),
        library("spectre", "passing", version: "0.3.2", version_source: "hex"),
        library("spectre_ledger", "passing"),
        library("spectre_lab", "passing")
      ]
    }
  end

  defp library(name, status, opts \\ []) do
    %{
      "name" => name,
      "status" => status,
      "version" => Keyword.get(opts, :version, "0.1.0"),
      "version_source" => Keyword.get(opts, :version_source, "github"),
      "repository_url" => "https://github.com/elchemista/#{name}",
      "version_url" => "https://github.com/elchemista/#{name}/blob/main/mix.exs",
      "check" => %{
        "run_url" => "https://github.com/elchemista/spectre_ecosystem/actions/runs/1"
      }
    }
  end
end
