defmodule ExBlogWeb.Router do
  use ExBlogWeb, :router

  import ExBlogWeb.AdminAuth

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

  pipeline :admin_browser do
    plug :put_security_headers
    plug :fetch_current_scope
  end

  pipeline :redirect_if_admin_authenticated do
    plug :redirect_if_authenticated
  end

  pipeline :require_admin_authenticated do
    plug :require_authenticated
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

  scope "/admin", ExBlogWeb.Admin do
    pipe_through [:browser, :admin_browser, :redirect_if_admin_authenticated]

    live_session :redirect_if_admin_authenticated,
      on_mount: [{ExBlogWeb.AdminAuth, :redirect_if_authenticated}] do
      live "/login", LoginLive, :new
    end

    post "/login", SessionController, :create
  end

  scope "/admin", ExBlogWeb.Admin do
    pipe_through [:browser, :admin_browser]

    delete "/logout", SessionController, :delete
  end

  scope "/admin", ExBlogWeb.Admin do
    pipe_through [:browser, :admin_browser, :require_admin_authenticated]

    live_session :require_admin_authenticated,
      on_mount: [{ExBlogWeb.AdminAuth, :require_authenticated}] do
      live "/telegram", TelegramLive, :show
    end
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
