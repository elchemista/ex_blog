defmodule ExBlog.Content.Parser do
  @moduledoc """
  Parses the repository Markdown contract into `ExBlog.Content.Article` values.

  Missing editorial fields receive deterministic defaults. Broken YAML,
  unknown statuses, invalid dates, and malformed front matter are reported to
  the index without crashing application boot.
  """

  alias ExBlog.Content.Article

  @front_matter ~r/\A(?:\x{FEFF})?---\r?\n(.*?)\r?\n---(?:\r?\n|\z)(.*)\z/su

  @spec parse_file(String.t(), keyword()) ::
          {:ok, Article.t()} | {:error, term(), String.t()}
  def parse_file(path, opts \\ []) do
    display_path = relative_path(path, Keyword.get(opts, :root))

    case File.read(path) do
      {:ok, source} ->
        case parse(source, display_path) do
          {:ok, article} -> {:ok, article}
          {:error, reason} -> {:error, reason, display_path}
        end

      {:error, reason} ->
        {:error, {:file_error, reason}, display_path}
    end
  end

  @spec parse(String.t(), String.t()) :: {:ok, Article.t()} | {:error, term()}
  def parse(source, path) when is_binary(source) and is_binary(path) do
    with {:ok, yaml, body} <- split(source),
         {:ok, metadata} <- decode_yaml(yaml),
         {:ok, status} <- status(metadata),
         {:ok, date} <- date(metadata, "date", path),
         {:ok, updated} <- date(metadata, "updated", path),
         {:ok, html} <- render(body) do
      slug = metadata_string(metadata, "slug") || infer_slug(path)
      lang = metadata_string(metadata, "lang") || infer_language(path)
      title = metadata_string(metadata, "title") || humanize(slug)

      if valid_slug?(slug) and valid_language?(lang) do
        {:ok,
         %Article{
           path: path,
           title: title,
           slug: slug,
           lang: lang,
           status: status,
           date: date,
           updated: updated || date,
           category: metadata_string(metadata, "category"),
           tags: tags(metadata),
           seo_title: metadata_string(metadata, "seo_title"),
           seo_description: metadata_string(metadata, "seo_description"),
           cover: metadata_string(metadata, "cover"),
           cover_alt: metadata_string(metadata, "cover_alt"),
           translation_of: metadata_string(metadata, "translation_of"),
           body: body,
           html: html,
           excerpt: excerpt(body),
           checksum: Article.checksum(source)
         }}
      else
        {:error, :invalid_slug_or_language}
      end
    end
  end

  defp split(source) do
    case Regex.run(@front_matter, source, capture: :all_but_first) do
      [yaml, body] -> {:ok, yaml, body}
      _other -> {:error, :missing_or_malformed_front_matter}
    end
  end

  defp decode_yaml(yaml) do
    case YamlElixir.read_from_string(yaml) do
      {:ok, metadata} when is_map(metadata) -> {:ok, metadata}
      {:ok, _other} -> {:error, :front_matter_must_be_a_map}
      {:error, reason} -> {:error, {:invalid_yaml, reason}}
    end
  rescue
    error -> {:error, {:invalid_yaml, Exception.message(error)}}
  end

  defp render(body) do
    MDEx.to_html(body,
      extension: [
        autolink: true,
        footnotes: true,
        strikethrough: true,
        table: true,
        tasklist: true
      ],
      parse: [smart: true],
      sanitize: MDEx.Document.default_sanitize_options()
    )
  rescue
    error -> {:error, {:invalid_markdown, Exception.message(error)}}
  end

  defp status(metadata) do
    case metadata_string(metadata, "status") || "draft" do
      "draft" -> {:ok, :draft}
      "published" -> {:ok, :published}
      other -> {:error, {:invalid_status, other}}
    end
  end

  defp date(metadata, field, path) do
    raw = metadata_string(metadata, field)
    raw = if field == "date", do: raw || infer_date(path), else: raw

    case raw do
      nil -> {:ok, nil}
      value -> parse_date(value, field)
    end
  end

  defp parse_date(value, field) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, {:invalid_date, field, value}}
    end
  end

  defp tags(metadata) do
    case Map.get(metadata, "tags", []) do
      values when is_list(values) ->
        values
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()

      value when is_binary(value) ->
        value
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      _other ->
        []
    end
  end

  defp excerpt(body) do
    body
    |> String.replace(~r/<(?:script|style)\b[^>]*>.*?<\/(?:script|style)\s*>/isu, " ")
    |> String.replace(~r/<[^>]+>/u, " ")
    |> String.replace(~r/```.*?```/s, " ")
    |> String.replace(~r/[#>*_`\[\]()!-]/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, 220)
  end

  defp infer_slug(path) do
    path
    |> Path.basename(Path.extname(path))
    |> String.replace(~r/^\d{4}-\d{2}-\d{2}-/, "")
  end

  defp infer_language(path) do
    path
    |> Path.dirname()
    |> Path.basename()
  end

  defp infer_date(path) do
    case Regex.run(~r/(\d{4}-\d{2}-\d{2})-/, Path.basename(path), capture: :all_but_first) do
      [date] -> date
      _other -> nil
    end
  end

  defp humanize(slug) do
    slug
    |> String.replace("-", " ")
    |> String.capitalize()
  end

  defp metadata_string(metadata, key) do
    case Map.get(metadata, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      %Date{} = value ->
        Date.to_iso8601(value)

      _other ->
        nil
    end
  end

  defp valid_slug?(slug),
    do: is_binary(slug) and Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, slug)

  defp valid_language?(lang),
    do: is_binary(lang) and Regex.match?(~r/^[a-z]{2}(?:-[A-Z]{2})?$/, lang)

  defp relative_path(path, nil), do: path
  defp relative_path(path, root), do: Path.relative_to(path, root)
end
