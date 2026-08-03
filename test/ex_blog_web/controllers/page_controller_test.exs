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
  end
end
