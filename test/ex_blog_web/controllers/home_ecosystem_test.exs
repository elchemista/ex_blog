defmodule ExBlogWeb.HomeEcosystemTest do
  # Starts the named ecosystem process and reads its named ETS table.
  use ExBlogWeb.ConnCase, async: false

  alias ExBlog.Ecosystem

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

    # The stub has to exist before the refresher may be allowed to use it.
    stub(report("passing"))

    pid =
      start_supervised!({Ecosystem, refresh_on_start?: false, url: "https://example.test/s.json"})

    :ok = Req.Test.allow(__MODULE__, self(), pid)

    {:ok, ecosystem: pid}
  end

  test "the home page renders the refreshed matrix", %{conn: conn, ecosystem: ecosystem} do
    stub(report("passing"))
    assert {:ok, _snapshot} = Ecosystem.refresh(ecosystem)

    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.query(document, "#spectre-compatibility") |> Enum.any?()
    assert LazyHTML.query(document, "#compat-spectre_ledger") |> Enum.any?()
    assert LazyHTML.query(document, "#compat-spectre_lab") |> Enum.any?()
  end

  test "a changed matrix invalidates the cached home page", %{conn: conn, ecosystem: ecosystem} do
    stub(report("passing"))
    assert {:ok, _snapshot} = Ecosystem.refresh(ecosystem)
    passing_etag = etag(conn)

    # Without the snapshot in the ETag source, the daily refresh would keep
    # answering 304 with yesterday's table.
    stub(report("failing"))
    assert {:ok, _snapshot} = Ecosystem.refresh(ecosystem)

    assert etag(conn) != passing_etag
  end

  defp etag(conn) do
    conn |> get(~p"/") |> get_resp_header("etag") |> List.first()
  end

  defp stub(payload) do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, payload) end)
  end

  defp report(status) do
    %{
      "generated_at" => "2026-08-16T13:16:15.773486Z",
      "libraries" =>
        Enum.map(~w(spectre spectre_ledger spectre_lab), fn name ->
          %{
            "name" => name,
            "status" => status,
            "version" => "0.1.0",
            "version_source" => "github",
            "repository_url" => "https://github.com/elchemista/#{name}"
          }
        end)
    }
  end
end
