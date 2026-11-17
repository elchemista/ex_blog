defmodule ExBlogWeb.GovernedActModelController do
  use ExBlogWeb, :controller

  alias ExBlog.Config
  alias ExBlog.GovernedActModel
  alias ExBlogWeb.PublicCache

  def show(conn, %{"lang" => language}) do
    case GovernedActModel.fetch(language) do
      {:ok, manifesto} ->
        _previous_locale = Gettext.put_locale(ExBlogWeb.Gettext, language)
        path = manifesto_path(language)

        assigns = [
          manifesto: manifesto,
          current_language: language,
          supported_languages: GovernedActModel.languages(),
          language_paths: language_paths(),
          page_language: language,
          page_title: page_title(language),
          meta_description: manifesto.summary,
          canonical_url: absolute_url(path),
          og_type: "article",
          og_image_alt: "Governed Act Model — #{manifesto.eyebrow}",
          alternates: alternates(),
          keywords:
            "Governed Act Model, agentic systems, AI agent governance, Mandate, Evidence, Act, Duty, Spectre",
          json_ld: json_ld(manifesto, path)
        ]

        PublicCache.render(conn, "governed-act-model:#{language}", &render(&1, :show, assigns))

      :error ->
        conn
        |> put_status(:not_found)
        |> put_resp_header("cache-control", "no-store")
        |> put_view(ExBlogWeb.BlogHTML)
        |> render(:not_found,
          current_language: Config.get().default_language,
          supported_languages: Config.get().supported_languages,
          page_title: gettext("Page not found"),
          meta_description: gettext("The requested page does not exist."),
          robots: "noindex,follow",
          canonical_url: Config.canonical_url()
        )
    end
  end

  defp page_title("it"), do: "Governed Act Model — Manifesto per sistemi agentici"
  defp page_title("en"), do: "Governed Act Model — A manifesto for agentic systems"

  defp language_paths do
    Map.new(GovernedActModel.languages(), &{&1, manifesto_path(&1)})
  end

  defp alternates do
    localized =
      Enum.map(GovernedActModel.languages(), fn language ->
        %{hreflang: language, url: absolute_url(manifesto_path(language))}
      end)

    localized ++ [%{hreflang: "x-default", url: absolute_url(manifesto_path("it"))}]
  end

  defp json_ld(manifesto, path) do
    url = absolute_url(path)

    %{
      "@context" => "https://schema.org",
      "@type" => "TechArticle",
      "@id" => url <> "#manifesto",
      "headline" => manifesto.title,
      "description" => manifesto.summary,
      "inLanguage" => manifesto.language,
      "url" => url,
      "wordCount" => manifesto.words,
      "about" => [
        %{"@type" => "Thing", "name" => "AI agent governance"},
        %{"@type" => "Thing", "name" => "Agentic systems"}
      ],
      "isPartOf" => %{"@type" => "WebSite", "@id" => Config.canonical_url() <> "/#website"}
    }
  end

  defp manifesto_path(language), do: "/#{language}/governed-act-model"
  defp absolute_url(path), do: Config.canonical_url() <> path
end
