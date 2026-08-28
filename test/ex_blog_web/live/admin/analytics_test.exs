defmodule ExBlogWeb.Admin.AnalyticsTest do
  @moduledoc """
  The traffic dashboard is evaluated in place: it is Phoenix Analytics rendering
  itself, so what is worth asserting is the wiring around it — who reaches it,
  which document carries it, and what the tracker does and does not record.
  """

  use ExBlogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.Services.Utility
  alias PhoenixAnalytics.Store

  @password "correct horse battery staple"

  setup do
    handler = "phoenix-analytics-#{System.unique_integer([:positive])}"
    test = self()

    :telemetry.attach_many(
      handler,
      [
        [:phoenix_analytics, :request, :tracked],
        [:phoenix_analytics, :request, :skipped]
      ],
      fn event, _measurements, metadata, _config ->
        send(test, {:analytics, List.last(event), metadata[:reason]})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    :ok
  end

  describe "access" do
    test "an anonymous visitor never reaches the dashboard", %{conn: conn} do
      conn = get(conn, ~p"/admin/analytics")

      assert redirected_to(conn) == ~p"/admin/login"
    end

    test "an administrator gets the dashboard and its live socket", %{conn: conn} do
      conn = log_in(conn)

      conn = get(conn, ~p"/admin/analytics")
      document = conn |> html_response(200) |> LazyHTML.from_document()

      assert Enum.count(LazyHTML.query(document, "#admin-analytics-back")) == 1

      assert LazyHTML.attribute(LazyHTML.query(document, "meta[name=robots]"), "content") ==
               ["noindex,nofollow,noarchive"]

      {:ok, view, _html} = conn |> recycle() |> live(~p"/admin/analytics")

      assert render(view) =~ "phx-hook"
    end

    test "the site bundle stays out of the dashboard document", %{conn: conn} do
      html = conn |> log_in() |> get(~p"/admin/analytics") |> html_response(200)

      # Two LiveSocket instances on one document fight over the same LiveView,
      # so the analytics assets replace the site's instead of joining them.
      refute html =~ "/assets/js/app.js"
      refute html =~ "/assets/css/app.css"
    end
  end

  describe "storage" do
    test "the dashboard reads the in-memory store, with no database behind it", %{conn: conn} do
      path = "/read-back-#{System.unique_integer([:positive])}"

      :ok =
        Store.insert_all([
          %RequestLog{
            request_id: Utility.uuid(),
            method: "GET",
            path: path,
            status_code: 200,
            duration_ms: 12,
            device_type: "desktop",
            session_id: "session",
            session_page_views: 1,
            inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
          }
        ])

      {:ok, view, _html} = conn |> log_in() |> live(~p"/admin/analytics")

      # The charts load through `assign_async`, so the first render is empty.
      assert render_async(view) =~ path
    end
  end

  describe "tracking" do
    test "a reader who accepted analytics is recorded", %{conn: conn} do
      conn |> consent(["necessary", "analytics"]) |> get(~p"/sitemap.xml")

      assert_receive {:analytics, :tracked, _reason}
    end

    test "the administrator area is left out of the numbers", %{conn: conn} do
      get(conn, ~p"/admin/login")

      assert_receive {:analytics, :skipped, :ignore_path}
    end
  end

  describe "consent" do
    test "a reader who has not answered the banner is not tracked", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")

      assert_receive {:analytics, :skipped, :before_plug}

      # Skipping happens before the tracker opens its session, so the request
      # that was not counted also leaves no cookie behind.
      assert conn.resp_cookies["pa_session_id"] == nil
      assert conn.resp_cookies["pa_page_views"] == nil
    end

    test "a reader who kept only necessary cookies is not tracked", %{conn: conn} do
      conn |> consent(["necessary"]) |> get(~p"/sitemap.xml")

      assert_receive {:analytics, :skipped, :before_plug}
    end

    test "a cookie the banner did not write is read as no consent", %{conn: conn} do
      # The value is client controlled, so anything unparseable must fall back to
      # the answer a first-time visitor gets rather than raise mid-request.
      for value <- ["", "not json", "%zz", ~s({"categories":"analytics"}), "[]"] do
        conn
        |> Plug.Test.put_req_cookie("spectre_cookie_consent", value)
        |> get(~p"/sitemap.xml")

        assert_receive {:analytics, :skipped, :before_plug}
      end
    end

    test "an oversized cookie never reaches the JSON parser", %{conn: conn} do
      padding = String.duplicate("a", 5_000)

      conn
      |> consent(["necessary", "analytics", padding])
      |> get(~p"/sitemap.xml")

      assert_receive {:analytics, :skipped, :before_plug}
    end
  end

  # Mirrors what the banner stores: `encodeURIComponent(JSON.stringify(state))`.
  defp consent(conn, categories) do
    value =
      %{"categories" => categories, "revision" => 0}
      |> Jason.encode!()
      |> URI.encode(&URI.char_unreserved?/1)

    Plug.Test.put_req_cookie(conn, "spectre_cookie_consent", value)
  end

  defp log_in(conn) do
    conn
    |> post(~p"/admin/login", %{"admin" => %{"password" => @password}})
    |> recycle()
  end
end
