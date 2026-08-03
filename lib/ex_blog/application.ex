defmodule ExBlog.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ExBlogWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:ex_blog, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ExBlog.PubSub},
      # Start a worker by calling: ExBlog.Worker.start_link(arg)
      # {ExBlog.Worker, arg},
      # Start to serve requests, typically the last entry
      ExBlogWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExBlog.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ExBlogWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
