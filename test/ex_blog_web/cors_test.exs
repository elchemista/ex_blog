defmodule ExBlogWeb.CORSTest do
  use ExBlogWeb.ConnCase, async: false

  @allowed_origin "https://spectre-blog.fly.dev"

  setup do
    previous_origins = Application.get_env(:ex_blog, :cors_origins)
    Application.put_env(:ex_blog, :cors_origins, [@allowed_origin])

    on_exit(fn ->
      if previous_origins do
        Application.put_env(:ex_blog, :cors_origins, previous_origins)
      else
        Application.delete_env(:ex_blog, :cors_origins)
      end
    end)
  end

  test "answers an allowed CORS preflight before routing", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", @allowed_origin)
      |> put_req_header("access-control-request-method", "GET")
      |> options("/health")

    assert response(conn, 204) == ""
    assert get_resp_header(conn, "access-control-allow-origin") == [@allowed_origin]
    assert get_resp_header(conn, "access-control-allow-credentials") == ["true"]

    assert "GET" in (conn
                     |> get_resp_header("access-control-allow-methods")
                     |> List.first()
                     |> String.split(","))
  end

  test "does not grant CORS access to an unlisted origin", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://attacker.example")
      |> get("/health")

    assert response(conn, 200)
    assert get_resp_header(conn, "access-control-allow-origin") == []
    assert get_resp_header(conn, "access-control-allow-credentials") == []
  end
end
