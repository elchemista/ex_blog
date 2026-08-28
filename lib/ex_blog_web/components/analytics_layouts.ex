defmodule ExBlogWeb.AnalyticsLayouts do
  @moduledoc """
  Document layout for the administrator traffic dashboard.

  Phoenix Analytics renders React charts through the LiveSocket it bundles
  itself, so the dashboard cannot share the public root layout: two LiveSocket
  instances on one document fight over the same LiveView. This layout loads the
  analytics assets instead of the site's, and adds the administrator navigation
  the library knows nothing about.
  """

  use ExBlogWeb, :html

  @doc "Root document of the administrator traffic dashboard."
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="[scrollbar-gutter:stable]">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <meta name="robots" content="noindex,nofollow,noarchive" />
        <title>{gettext("Traffic")} · {Layouts.site_name()}</title>
        <PhoenixAnalytics.Web.Layouts.analytics_head />
      </head>
      <body class="bg-background text-foreground">
        <nav class="mx-auto flex max-w-screen-lg items-center justify-between gap-4 px-4 py-2 text-sm sm:px-6">
          <%!-- A plain link, not live navigation: the administrator pages and the
          dashboard load different bundles, so the transition is a full one. --%>
          <.link id="admin-analytics-back" href={~p"/admin/telegram"} class="hover:underline">
            {gettext("Administration")}
          </.link>
          <.link
            href={~p"/admin/logout"}
            method="delete"
            class="text-muted-foreground hover:underline"
          >
            exit
          </.link>
        </nav>
        {@inner_content}
      </body>
    </html>
    """
  end
end
