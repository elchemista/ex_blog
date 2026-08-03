defmodule ExBlog.Release do
  @moduledoc false

  @app :ex_blog

  def migrate do
    :ok = load_app()

    Enum.each(Application.fetch_env!(@app, :ecto_repos), fn repo ->
      {:ok, _pid, _apps} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end)

    :ok
  end

  defp load_app do
    case Application.load(@app) do
      :ok -> :ok
      {:error, {:already_loaded, @app}} -> :ok
      {:error, reason} -> raise "could not load #{@app}: #{inspect(reason)}"
    end
  end
end
