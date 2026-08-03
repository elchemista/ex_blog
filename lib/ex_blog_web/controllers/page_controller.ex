defmodule ExBlogWeb.PageController do
  use ExBlogWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
