defmodule ExBlogWeb.OAuthHTML do
  @moduledoc "Consent templates for the administrator-authorized MCP connection."

  use ExBlogWeb, :html

  embed_templates "oauth_html/*"

  def scope_label("offline_access"),
    do: gettext("Keep the connection alive until it is revoked")

  def scope_label("articles:read"),
    do: gettext("Read articles, safe configuration and operational status")

  def scope_label("articles:write"),
    do: gettext("Create and edit content only through the authorized tools")

  def scope_label(scope), do: scope
end
