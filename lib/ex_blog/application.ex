defmodule ExBlog.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    config = load_runtime_config!()
    File.mkdir_p!(config.data_dir)

    if Application.get_env(:ex_blog, :auto_migrate?, false) do
      :ok = ExBlog.Release.migrate()
    end

    children =
      [
        ExBlog.Repo,
        ExBlogWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:ex_blog, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: ExBlog.PubSub},
        ExBlog.Admin.LoginThrottle
      ] ++ content_children() ++ telegram_children() ++ [ExBlogWeb.Endpoint]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExBlog.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp content_children do
    if Application.get_env(:ex_blog, :start_content?, true) do
      [ExBlog.Content.Bootstrap, ExBlog.Content.Index, ExBlog.Content.Sync]
    else
      []
    end
  end

  defp telegram_children do
    if Application.get_env(:ex_blog, :start_telegram?, true) do
      [ExBlog.Telegram.Transport]
    else
      []
    end
  end

  defp load_runtime_config! do
    environment = Application.get_env(:ex_blog, :runtime_environment, :dev)

    config =
      if Application.get_env(:ex_blog, :validate_runtime_config?, true) do
        ExBlog.Config.load!(System.get_env(), production?: environment == :prod)
      else
        ExBlog.Config.test_config(
          data_dir: Application.fetch_env!(:ex_blog, :runtime_data_dir),
          phx_host: "localhost"
        )
      end

    :ok = ExBlog.Config.install(config)
    config
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ExBlogWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
