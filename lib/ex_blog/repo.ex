defmodule ExBlog.Repo do
  use Ecto.Repo,
    otp_app: :ex_blog,
    adapter: Ecto.Adapters.SQLite3
end
