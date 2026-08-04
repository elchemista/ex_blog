defmodule ExBlogWeb.PublicHomeTest do
  use ExBlogWeb.ConnCase

  test "GET / renders the blog shell without indexed content", %{conn: conn} do
    document =
      conn
      |> get(~p"/")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#blog-index") |> Enum.count() == 1
    assert document |> LazyHTML.query("#articles-empty") |> Enum.count() == 1

    assert document |> LazyHTML.query(~s(link[rel="icon"][href="/favicon.svg"])) |> Enum.count() ==
             1
  end

  test "serves the Spectre ghost favicon", %{conn: conn} do
    favicon_response = get(conn, ~p"/favicon.svg")

    assert response(favicon_response, 200) =~ ~s(aria-label="Spectre ghost")
    assert get_resp_header(favicon_response, "content-type") == ["image/svg+xml"]
  end
end
