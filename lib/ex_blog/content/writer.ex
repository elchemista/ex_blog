defmodule ExBlog.Content.Writer do
  @moduledoc """
  Strict write boundary for canonical article files.

  Every target is resolved beneath the configured content directory before a
  filesystem mutation. Successful writes are committed, pushed, and followed
  by a complete index rebuild.
  """

  alias ExBlog.Config
  alias ExBlog.Content
  alias ExBlog.Content.Article
  alias ExBlog.Content.Git
  alias ExBlog.Content.Index

  @fields [
    :title,
    :slug,
    :lang,
    :status,
    :date,
    :updated,
    :category,
    :tags,
    :seo_title,
    :seo_description,
    :cover,
    :cover_alt,
    :translation_of,
    :body
  ]

  @spec create(map(), keyword()) :: {:ok, Article.t()} | {:error, term()}
  def create(params, opts \\ []) when is_map(params) do
    config = Keyword.get(opts, :config, Config.get())

    with {:ok, attrs} <- normalize_create(params, config),
         {:error, :not_found} <- Content.get(attrs.lang, attrs.slug, published_only?: false),
         relative_path <- article_path(attrs, config),
         {:ok, absolute_path} <- safe_target(relative_path, config),
         :ok <- File.mkdir_p(Path.dirname(absolute_path)),
         :ok <- File.write(absolute_path, serialize(attrs)),
         {:ok, _commit} <-
           commit_and_maybe_push([relative_path], "Create #{attrs.lang}/#{attrs.slug}", opts),
         {:ok, _summary} <- Index.rebuild(),
         {:ok, article} <- Content.get(attrs.lang, attrs.slug, published_only?: false) do
      {:ok, article}
    else
      {:ok, %Article{}} -> {:error, :article_already_exists}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update(Article.t(), map(), keyword()) :: {:ok, Article.t()} | {:error, term()}
  def update(%Article{valid?: true} = article, params, opts \\ []) when is_map(params) do
    config = Keyword.get(opts, :config, Config.get())

    with {:ok, attrs} <- normalize_update(article, params, config),
         {:ok, absolute_path} <- safe_target(article.path, config),
         :ok <- File.write(absolute_path, serialize(attrs)),
         {:ok, _commit} <-
           commit_and_maybe_push([article.path], "Update #{article.lang}/#{article.slug}", opts),
         {:ok, _summary} <- Index.rebuild() do
      Content.get(attrs.lang, attrs.slug, published_only?: false)
    end
  end

  @spec publish(Article.t(), keyword()) :: {:ok, Article.t()} | {:error, term()}
  def publish(%Article{} = article, opts \\ []),
    do: update(article, %{status: :published, updated: Date.utc_today()}, opts)

  @spec unpublish(Article.t(), keyword()) :: {:ok, Article.t()} | {:error, term()}
  def unpublish(%Article{} = article, opts \\ []),
    do: update(article, %{status: :draft, updated: Date.utc_today()}, opts)

  @spec delete(Article.t(), keyword()) :: :ok | {:error, term()}
  def delete(%Article{valid?: true} = article, opts \\ []) do
    config = Keyword.get(opts, :config, Config.get())

    with {:ok, absolute_path} <- safe_target(article.path, config),
         :ok <- File.rm(absolute_path),
         {:ok, _commit} <-
           commit_and_maybe_push([article.path], "Delete #{article.lang}/#{article.slug}", opts),
         {:ok, _summary} <- Index.rebuild() do
      :ok
    end
  end

  @spec serialize(map()) :: String.t()
  def serialize(attrs) do
    front_matter =
      @fields
      |> Enum.reject(&(&1 == :body))
      |> Enum.flat_map(fn field -> yaml_line(field, Map.get(attrs, field)) end)
      |> Enum.join("\n")

    "---\n#{front_matter}\n---\n\n#{String.trim(Map.fetch!(attrs, :body))}\n"
  end

  defp normalize_create(params, config) do
    title = get(params, :title)
    body = get(params, :body)
    lang = get(params, :lang) || config.default_language
    slug = get(params, :slug) || if(is_binary(title), do: Slug.slugify(title))
    date = normalize_date(get(params, :date)) || Date.utc_today()

    attrs = %{
      title: normalize_string(title),
      slug: normalize_string(slug),
      lang: normalize_string(lang),
      status: normalize_status(get(params, :status) || :draft),
      date: date,
      updated: normalize_date(get(params, :updated)) || date,
      category: normalize_string(get(params, :category)),
      tags: normalize_tags(get(params, :tags)),
      seo_title: normalize_string(get(params, :seo_title)),
      seo_description: normalize_string(get(params, :seo_description)),
      cover: normalize_string(get(params, :cover)),
      cover_alt: normalize_string(get(params, :cover_alt)),
      translation_of: normalize_string(get(params, :translation_of)),
      body: normalize_string(body)
    }

    validate(attrs, config)
  end

  defp normalize_update(article, params, config) do
    current = Map.from_struct(article)

    attrs =
      @fields
      |> Enum.reduce(%{}, fn field, acc ->
        value = if has_key?(params, field), do: get(params, field), else: Map.get(current, field)
        Map.put(acc, field, normalize_field(field, value))
      end)
      |> Map.put(:slug, article.slug)
      |> Map.put(:lang, article.lang)
      |> Map.put(:date, article.date || Date.utc_today())

    validate(attrs, config)
  end

  defp validate(attrs, config) do
    with :ok <- required(attrs.title, :title),
         :ok <- required(attrs.body, :body),
         :ok <- valid_slug(attrs.slug),
         :ok <- supported_language(attrs.lang, config),
         :ok <- valid_status(attrs.status),
         :ok <- maximum_length(attrs.seo_title, 60, :seo_title_too_long),
         :ok <- maximum_length(attrs.seo_description, 160, :seo_description_too_long) do
      {:ok, attrs}
    end
  end

  defp required(nil, field), do: {:error, {:missing_field, field}}
  defp required(_value, _field), do: :ok

  defp valid_slug(slug) when is_binary(slug) do
    if Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, slug),
      do: :ok,
      else: {:error, :invalid_slug}
  end

  defp valid_slug(_slug), do: {:error, :invalid_slug}

  defp supported_language(language, config) do
    if language in config.supported_languages,
      do: :ok,
      else: {:error, :unsupported_language}
  end

  defp valid_status(status) do
    if status in [:draft, :published], do: :ok, else: {:error, :invalid_status}
  end

  defp maximum_length(nil, _maximum, _error), do: :ok

  defp maximum_length(value, maximum, error) do
    if String.length(value) <= maximum, do: :ok, else: {:error, error}
  end

  defp article_path(attrs, config) do
    filename = "#{Date.to_iso8601(attrs.date)}-#{attrs.slug}.md"
    Path.join([config.content_root, attrs.lang, filename])
  end

  defp safe_target(relative_path, config) do
    checkout = Config.repository_path(config)
    content = Path.expand(config.content_root, checkout)
    target = Path.expand(relative_path, checkout)

    if target != content and String.starts_with?(target, content <> "/") do
      {:ok, target}
    else
      {:error, :unsafe_content_path}
    end
  end

  defp commit_and_maybe_push(paths, message, opts) do
    config = Keyword.get(opts, :config, Config.get())
    git_opts = [config: config, path: Config.repository_path(config)]

    with {:ok, commit} <- Git.commit(paths, message, git_opts) do
      if Keyword.get(opts, :push?, true) and commit != :noop do
        Git.push(git_opts)
      else
        {:ok, commit}
      end
    end
  end

  defp yaml_line(_field, nil), do: []

  defp yaml_line(field, %Date{} = value),
    do: ["#{field}: #{Date.to_iso8601(value)}"]

  defp yaml_line(field, value) when is_atom(value),
    do: ["#{field}: #{value}"]

  defp yaml_line(field, value) when is_list(value),
    do: ["#{field}: #{Jason.encode!(value)}"]

  defp yaml_line(field, value),
    do: ["#{field}: #{Jason.encode!(to_string(value))}"]

  defp normalize_field(:status, value), do: normalize_status(value)
  defp normalize_field(field, value) when field in [:date, :updated], do: normalize_date(value)
  defp normalize_field(:tags, value), do: normalize_tags(value)
  defp normalize_field(_field, value), do: normalize_string(value)

  defp normalize_status(value) when value in [:draft, "draft"], do: :draft
  defp normalize_status(value) when value in [:published, "published"], do: :published
  defp normalize_status(_value), do: :invalid

  defp normalize_date(%Date{} = date), do: date

  defp normalize_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp normalize_date(_value), do: nil

  defp normalize_tags(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_tags(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> normalize_tags()
  end

  defp normalize_tags(_value), do: []

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(_value), do: nil

  defp get(map, field), do: Map.get(map, field, Map.get(map, Atom.to_string(field)))

  defp has_key?(map, field),
    do: Map.has_key?(map, field) or Map.has_key?(map, Atom.to_string(field))
end
