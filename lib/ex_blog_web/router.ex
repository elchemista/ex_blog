defmodule ExBlogWeb.Router do
  use ExBlogWeb, :router
  use PhoenixAnalytics.Web, :router

  import ExBlogWeb.AdminAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExBlogWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug ExBlogWeb.Plugs.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # robots.txt and the sitemap are crawler documents, not browser pages: a bot
  # that asks for `text/plain` or `application/xml` must not get a 406 from an
  # HTML-only negotiation.
  pipeline :crawler do
    plug :accepts, ["txt", "xml", "html"]
    plug :put_secure_browser_headers
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
    get "/feed.xml", FeedController, :rss
    get "/atom.xml", FeedController, :atom
    get "/cookies-policy", LegalController, :cookie_policy
    get "/privacy-policy", LegalController, :privacy_policy
    get "/gdpr-policy", LegalController, :gdpr_policy
  end

  scope "/", ExBlogWeb do
    pipe_through :crawler

    get "/robots.txt", RobotsController, :show
    get "/sitemap.xml", SitemapController, :show
  end

  scope "/admin", ExBlogWeb.Admin do
    pipe_through [:browser, :admin_browser, :redirect_if_admin_authenticated]

    live_session :redirect_if_admin_authenticated,
      on_mount: [{ExBlogWeb.AdminAuth, :redirect_if_authenticated}, ExBlogWeb.LocaleLive] do
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
      on_mount: [{ExBlogWeb.AdminAuth, :require_authenticated}, ExBlogWeb.LocaleLive] do
      live "/telegram", TelegramLive, :show
    end

    # The traffic dashboard ships its own LiveView, React bundle and document,
    # so it gets its own live session rather than a panel inside an existing
    # administrator page. Authentication is the same one: the pipeline above
    # guards the first request and the mount hook guards the socket.
    phoenix_analytics_dashboard("/analytics",
      as: :admin_analytics,
      on_mount: [{ExBlogWeb.AdminAuth, :require_authenticated}],
      root_layout: {ExBlogWeb.AnalyticsLayouts, :root}
    )
  end

  # ChatGPT discovers these documents before it starts the OAuth flow.
  scope "/.well-known", ExBlogWeb do
    pipe_through :api

    get "/oauth-protected-resource", OAuthMetadataController, :protected_resource
    get "/oauth-protected-resource/mcp", OAuthMetadataController, :protected_resource
    get "/oauth-authorization-server", OAuthMetadataController, :authorization_server
  end

  # Dynamic registration and token exchange are JSON protocol endpoints.
  scope "/oauth", ExBlogWeb do
    pipe_through :api

    post "/register", OAuthController, :register
    post "/token", OAuthController, :token
    post "/revoke", OAuthController, :revoke
  end

  # Consent reuses the password-protected administrator browser session.
  scope "/oauth", ExBlogWeb do
    pipe_through [:browser, :admin_browser, :require_admin_authenticated]

    get "/authorize", OAuthController, :authorize
    post "/authorize", OAuthController, :decide
  end

  scope "/", ExBlogWeb do
    pipe_through :mcp

    post "/mcp", MCPController, :create
    get "/mcp", MCPController, :method_not_allowed
    delete "/mcp", MCPController, :method_not_allowed
  end

  scope "/", ExBlogWeb do
    pipe_through :browser

    get "/:lang/cookies-policy", LegalController, :cookie_policy
    get "/:lang/privacy-policy", LegalController, :privacy_policy
    get "/:lang/gdpr-policy", LegalController, :gdpr_policy
    get "/:lang/:slug", BlogController, :show
    get "/:lang", BlogController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", ExBlogWeb do
  #   pipe_through :api
  # end
end
