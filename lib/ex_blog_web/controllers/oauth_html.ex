defmodule ExBlogWeb.OAuthHTML do
  @moduledoc "Consent templates for the administrator-authorized MCP connection."

  use ExBlogWeb, :html

  embed_templates "oauth_html/*"

  def scope_label("offline_access"), do: "Mantieni attiva la connessione fino alla revoca"
  def scope_label("articles:read"), do: "Leggi articoli, configurazione sicura e stato operativo"

  def scope_label("articles:write"),
    do: "Crea e modifica contenuti solamente attraverso gli strumenti autorizzati"

  def scope_label(scope), do: scope
end
