defmodule ExBlogWeb.LegalController do
  use ExBlogWeb, :controller

  alias ExBlog.Config
  alias ExBlogWeb.LegalCopy

  @site_url "https://spectre.elchemista.com"

  def cookie_policy(conn, params), do: render_policy(conn, params, :cookie)
  def privacy_policy(conn, params), do: render_policy(conn, params, :privacy)
  def gdpr_policy(conn, params), do: render_policy(conn, params, :privacy)

  defp render_policy(conn, params, kind) do
    language = Map.get(params, "lang", Config.get().default_language)

    if language in Config.get().supported_languages do
      policy = policy_copy(kind, language)
      canonical_path = canonical_path(kind, language)

      render(conn, template(kind),
        policy: policy,
        site_name: LegalCopy.site_name(),
        site_domain: LegalCopy.site_domain(),
        contact_email: LegalCopy.contact_email(),
        current_language: language,
        supported_languages: Config.get().supported_languages,
        page_language: language,
        page_title: policy.title,
        meta_description: policy.summary,
        canonical_url: @site_url <> canonical_path,
        og_type: "website"
      )
    else
      send_resp(conn, :not_found, "Not found")
    end
  end

  defp policy_copy(:cookie, language), do: LegalCopy.cookie_policy(language)
  defp policy_copy(:privacy, language), do: LegalCopy.privacy_policy(language)

  defp template(:cookie), do: :cookie_policy
  defp template(:privacy), do: :privacy_policy

  defp canonical_path(:cookie, language), do: "/#{language}/cookies-policy"
  defp canonical_path(:privacy, language), do: "/#{language}/privacy-policy"
end
