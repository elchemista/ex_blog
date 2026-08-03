defmodule ExBlogWeb.Router do
  use ExBlogWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExBlogWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :mcp do
    plug ExBlogWeb.Plugs.MCPSecurity
  end

  scope "/", ExBlogWeb do
    pipe_through :browser

    get "/", BlogController, :home
    get "/health", HealthController, :show
    get "/tag/:tag", BlogController, :tag
    get "/category/:category", BlogController, :category
    get "/sitemap.xml", FeedController, :sitemap
    get "/robots.txt", FeedController, :robots
    get "/feed.xml", FeedController, :rss
    get "/atom.xml", FeedController, :atom
  end

  scope "/", ExBlogWeb do
    pipe_through :mcp

    post "/mcp", MCPController, :create
    get "/mcp", MCPController, :method_not_allowed
    delete "/mcp", MCPController, :method_not_allowed
  end

  scope "/", ExBlogWeb do
    pipe_through :browser

    get "/:lang/:slug", BlogController, :show
    get "/:lang", BlogController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", ExBlogWeb do
  #   pipe_through :api
  # end
end
