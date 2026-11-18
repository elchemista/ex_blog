defmodule ExBlogWeb.DocumentationController do
  @moduledoc "Serves the bundled, versioned Spectre documentation."
  use ExBlogWeb, :controller

  alias ExBlog.Config
  alias ExBlog.Documentation
  alias ExBlogWeb.PublicCache

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, %{"lang" => language}), do: render_page(conn, language, nil)
  def index(conn, _params), do: redirect(conn, to: "/#{default_language()}/docs")

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"lang" => language, "slug" => slug}),
    do: render_page(conn, language, slug)

  def show(conn, %{"slug" => slug}),
    do: redirect(conn, to: "/#{default_language()}/docs/#{URI.encode(slug)}")

  defp render_page(conn, language, slug) do
    case page(language, slug) do
      {:ok, document} ->
        _previous = Gettext.put_locale(ExBlogWeb.Gettext, language)
        chapters = Documentation.chapters(language)
        current = Enum.find_index(chapters, &(&1.slug == slug))
        path = documentation_path(language, slug)
        copy = copy(language)
        title = if document, do: document.title, else: copy.title
        description = if document, do: document.description, else: copy.summary

        assigns = [
          document: document,
          chapters: chapters,
          copy: copy,
          version: Documentation.version(),
          previous_chapter: adjacent(chapters, current, -1),
          next_chapter: adjacent(chapters, current, 1),
          current_language: language,
          supported_languages: Documentation.languages(),
          language_paths: Map.new(Documentation.languages(), &{&1, documentation_path(&1, slug)}),
          page_language: language,
          page_title: "#{title} — Spectre #{Documentation.version()}",
          meta_description: description,
          canonical_url: absolute(path),
          alternates: alternates(slug),
          og_type: "article",
          json_ld: %{
            "@context" => "https://schema.org",
            "@type" => if(document, do: "TechArticle", else: "CollectionPage"),
            "headline" => title,
            "description" => description,
            "inLanguage" => language,
            "version" => Documentation.version(),
            "url" => absolute(path)
          }
        ]

        PublicCache.render(
          conn,
          "docs:#{language}:#{slug || "index"}",
          &render(&1, :show, assigns)
        )

      :error ->
        conn
        |> put_status(:not_found)
        |> put_resp_header("cache-control", "no-store")
        |> put_view(ExBlogWeb.BlogHTML)
        |> render(:not_found,
          current_language: default_language(),
          supported_languages: Documentation.languages(),
          page_title: "Documentation not found",
          meta_description: "The requested documentation page does not exist.",
          robots: "noindex,follow",
          canonical_url: absolute("/#{default_language()}/docs")
        )
    end
  end

  defp page(language, slug) do
    cond do
      language not in Documentation.languages() -> :error
      is_nil(slug) -> {:ok, nil}
      true -> Documentation.fetch(language, slug)
    end
  end

  defp adjacent(_chapters, nil, _offset), do: nil
  defp adjacent(_chapters, 0, -1), do: nil
  defp adjacent(chapters, index, offset), do: Enum.at(chapters, index + offset)

  defp alternates(slug) do
    Enum.map(
      Documentation.languages(),
      &%{hreflang: &1, url: absolute(documentation_path(&1, slug))}
    ) ++
      [%{hreflang: "x-default", url: absolute(documentation_path(default_language(), slug))}]
  end

  defp documentation_path(language, nil), do: "/#{language}/docs"
  defp documentation_path(language, slug), do: "/#{language}/docs/#{slug}"
  defp absolute(path), do: Config.canonical_url() <> path

  defp default_language do
    language = Config.get().default_language
    if language in Documentation.languages(), do: language, else: "en"
  end

  defp copy("it") do
    %{
      title: "Documentazione Spectre",
      summary:
        "Avvia il primo agente, segui un input fino alla risposta e integra la tua libreria Elixir.",
      chapters: "Guide e riferimento",
      contents: "In questa pagina",
      previous: "Precedente",
      next: "Successiva",
      introduction: "Dalla prima conversazione alle integrazioni in produzione",
      source: "Sorgente della guida",
      edition: "Edizione",
      note:
        "Parti da «Il tuo primo AgentServer». Le guide successive mostrano un invio con consenso, tutte le callback e un client di fatturazione."
    }
  end

  defp copy("en") do
    %{
      title: "Spectre documentation",
      summary:
        "Start your first agent, trace an input to its reply, and integrate your own Elixir library.",
      chapters: "Guides and reference",
      contents: "On this page",
      previous: "Previous",
      next: "Next",
      introduction: "From the first conversation to production integrations",
      source: "Guide source",
      edition: "Edition",
      note:
        "Start with “Build your first AgentServer”. Then try delivery with consent, look up a callback, or connect your billing client."
    }
  end
end
