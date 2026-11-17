defmodule ExBlog.Documentation do
  @moduledoc """
  Bundled Spectre 0.4 guides, rendered once when the application is compiled.

  Language and chapter lookups use a closed catalogue. Requests never read a
  user-selected file, create atoms or contact the content repository.
  """

  @version "0.4.0"
  @pattern Path.expand("../../priv/spectre_docs/{en,it}/*.md", __DIR__)
  @paths Path.wildcard(@pattern)
  @languages ["en", "it"]
  @sanitize Keyword.put(MDEx.Document.default_sanitize_options(), :add_generic_attributes, ["id"])

  @documents Enum.map(@paths, fn path ->
               @external_resource path
               language = path |> Path.dirname() |> Path.basename()
               filename = Path.basename(path, ".md")
               slug = String.replace(filename, ~r/^\d+-/, "")
               source = File.read!(path)
               [heading, body] = String.split(source, "\n", parts: 2)
               "# " <> title = String.trim(heading)

               description =
                 body
                 |> String.trim()
                 |> String.split(~r/\n\s*\n/, parts: 2)
                 |> hd()
                 |> String.replace(~r/\s+/, " ")
                 |> String.replace(~r/\[([^\]]+)\]\([^)]+\)/, "\\1")
                 |> String.replace(~r/[`*_]/, "")
                 |> String.slice(0, 160)

               sections =
                 body
                 |> String.replace(~r/^```.*?^```[^\n]*$/ms, "")
                 |> then(&Regex.scan(~r/^##\s+(.+?)\s*$/mu, &1, capture: :all_but_first))
                 |> Enum.map(fn [title] -> %{title: title, id: MDEx.anchorize(title)} end)

               {:ok, html} =
                 MDEx.to_html(body,
                   extension: [
                     autolink: true,
                     table: true,
                     strikethrough: true,
                     header_id_prefix: ""
                   ],
                   parse: [smart: true],
                   sanitize: @sanitize
                 )

               %{
                 slug: slug,
                 language: language,
                 title: title,
                 description: description,
                 sections: sections,
                 html: html,
                 file: "priv/spectre_docs/#{language}/#{Path.basename(path)}"
               }
             end)
             |> Enum.group_by(& &1.language)

  @doc "The version documented by this edition."
  @spec version() :: String.t()
  def version, do: @version

  @doc "Languages with reviewed bundled guides."
  @spec languages() :: [String.t()]
  def languages, do: @languages

  @doc "Returns chapters in reading order; unsupported languages have no chapters."
  @spec chapters(String.t()) :: [map()]
  def chapters(language), do: Map.get(@documents, language, [])

  @doc "Looks up a chapter without filesystem access."
  @spec fetch(String.t(), String.t()) :: {:ok, map()} | :error
  def fetch(language, slug) do
    case Enum.find(chapters(language), &(&1.slug == slug)) do
      nil -> :error
      document -> {:ok, document}
    end
  end

  @doc false
  @spec __mix_recompile__?() :: boolean()
  def __mix_recompile__?, do: Path.wildcard(@pattern) != @paths
end
