defmodule ExBlog.Content do
  @moduledoc """
  Deterministic read API over the current content index.
  """

  alias ExBlog.Config
  alias ExBlog.Content.Article
  alias ExBlog.Content.Index

  @spec list(keyword()) :: [Article.t()]
  def list(opts \\ []) do
    language = Keyword.get(opts, :lang, Config.get().default_language)
    status = Keyword.get(opts, :status, :published)

    Index.all()
    |> Enum.filter(&(matches_language?(&1, language) and matches_status?(&1, status)))
    |> Enum.sort_by(&sort_date/1, {:desc, Date})
  end

  @spec get(String.t(), String.t(), keyword()) :: {:ok, Article.t()} | {:error, :not_found}
  def get(lang, slug, opts \\ []) do
    case Index.get(lang, slug) do
      %Article{valid?: true} = article ->
        if Keyword.get(opts, :published_only?, true) and not Article.published?(article),
          do: {:error, :not_found},
          else: {:ok, article}

      _other ->
        {:error, :not_found}
    end
  end

  @spec by_tag(String.t(), keyword()) :: [Article.t()]
  def by_tag(tag, opts \\ []) do
    opts
    |> list()
    |> Enum.filter(&(tag in &1.tags))
  end

  @spec by_category(String.t(), keyword()) :: [Article.t()]
  def by_category(category, opts \\ []) do
    opts
    |> list()
    |> Enum.filter(&(&1.category == category))
  end

  @spec search(String.t(), keyword()) :: [Article.t()]
  def search(query, opts \\ []) do
    needle = query |> String.trim() |> String.downcase()

    opts
    |> list()
    |> Enum.filter(fn article -> needle == "" or String.contains?(haystack(article), needle) end)
  end

  @spec invalid() :: [Article.t()]
  def invalid do
    Index.all()
    |> Enum.reject(& &1.valid?)
    |> Enum.sort_by(& &1.path)
  end

  @spec translations(Article.t()) :: [Article.t()]
  def translations(%Article{} = article) do
    origin = article.translation_of || article.path

    Index.all()
    |> Enum.filter(&(&1.valid? and (&1.path == origin or &1.translation_of == origin)))
    |> Enum.sort_by(& &1.lang)
  end

  @spec stats() :: map()
  def stats do
    base = Index.stats()

    languages =
      Index.all()
      |> Enum.filter(& &1.valid?)
      |> Enum.frequencies_by(& &1.lang)

    Map.put(base, :languages, languages)
  end

  defp matches_language?(%Article{valid?: false}, _language), do: false
  defp matches_language?(_article, :all), do: true
  defp matches_language?(article, language), do: article.lang == language

  defp matches_status?(article, :all), do: article.valid?
  defp matches_status?(article, status), do: article.valid? and article.status == status

  defp haystack(article) do
    [article.title, article.body, article.category, Enum.join(article.tags, " ")]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp sort_date(%Article{date: %Date{} = date}), do: date
  defp sort_date(%Article{}), do: ~D[0000-01-01]
end
