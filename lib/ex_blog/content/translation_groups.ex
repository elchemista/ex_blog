defmodule ExBlog.Content.TranslationGroups do
  @moduledoc """
  Resolves explicit and legacy article translation groups.

  New translations share the canonical repository path through
  `Article.translation_of`. Older content may predate that field. For those
  rows only, articles published on the same date are paired when they are the
  sole variants for that date or when their normalized tag overlap is the
  unique, mutual best match. Ambiguous rows remain separate so hreflang never
  guesses between equally plausible pages.
  """

  alias ExBlog.Config
  alias ExBlog.Content.Article

  @spec groups([Article.t()]) :: [[Article.t()]]
  def groups(articles) when is_list(articles) do
    articles = Enum.filter(articles, & &1.valid?)

    referenced_paths =
      articles
      |> Enum.flat_map(fn
        %Article{translation_of: path} when is_binary(path) -> [path]
        %Article{} -> []
      end)
      |> MapSet.new()

    {explicit, legacy} =
      Enum.split_with(articles, fn article ->
        is_binary(article.translation_of) or MapSet.member?(referenced_paths, article.path)
      end)

    explicit_groups =
      explicit
      |> Enum.group_by(&(&1.translation_of || &1.path))
      |> Map.values()

    (explicit_groups ++ legacy_groups(legacy))
    |> Enum.map(&sort_group/1)
    |> Enum.sort_by(fn group -> group |> List.first() |> article_order() end)
  end

  @spec for_article([Article.t()], Article.t()) :: [Article.t()]
  def for_article(articles, %Article{} = article) when is_list(articles) do
    Enum.find(groups(articles), [article], fn group ->
      Enum.any?(group, &(&1.path == article.path))
    end)
  end

  defp legacy_groups(articles) do
    {dated, undated} = Enum.split_with(articles, &match?(%Date{}, &1.date))

    dated_groups =
      dated
      |> Enum.group_by(& &1.date)
      |> Enum.sort_by(&elem(&1, 0), Date)
      |> Enum.flat_map(fn {_date, same_date} -> same_date_groups(same_date) end)

    dated_groups ++ Enum.map(undated, &[&1])
  end

  defp same_date_groups(articles) do
    by_language = Enum.group_by(articles, & &1.lang)

    by_language
    |> language_order()
    |> Enum.reduce([], fn language, groups ->
      attach_language(groups, Map.fetch!(by_language, language))
    end)
  end

  defp attach_language([], articles), do: Enum.map(sort_articles(articles), &[&1])

  defp attach_language([group], [article]), do: [group ++ [article]]

  defp attach_language(groups, articles) do
    articles = sort_articles(articles)

    edges =
      for {group, group_index} <- Enum.with_index(groups), article <- articles do
        %{
          group_index: group_index,
          article: article,
          score: Enum.map(group, &tag_similarity(&1, article)) |> Enum.max(fn -> 0 end)
        }
      end

    article_choices =
      edges
      |> Enum.group_by(& &1.article.path)
      |> Map.new(fn {path, choices} -> {path, unique_best(choices, & &1.group_index)} end)

    group_choices =
      edges
      |> Enum.group_by(& &1.group_index)
      |> Map.new(fn {index, choices} -> {index, unique_best(choices, & &1.article.path)} end)

    matches =
      Enum.filter(edges, fn edge ->
        edge.score > 0 and Map.get(article_choices, edge.article.path) == edge.group_index and
          Map.get(group_choices, edge.group_index) == edge.article.path
      end)

    matches_by_group = Map.new(matches, &{&1.group_index, &1.article})
    matched_paths = MapSet.new(matches, & &1.article.path)

    matched_groups =
      groups
      |> Enum.with_index()
      |> Enum.map(fn {group, index} ->
        case Map.get(matches_by_group, index) do
          %Article{} = article -> group ++ [article]
          nil -> group
        end
      end)

    unmatched_groups =
      articles
      |> Enum.reject(&MapSet.member?(matched_paths, &1.path))
      |> Enum.map(&[&1])

    matched_groups ++ unmatched_groups
  end

  defp unique_best(choices, value) do
    case Enum.sort_by(choices, &{-&1.score, value.(&1)}) do
      [best] -> value.(best)
      [best, next | _rest] when best.score > next.score -> value.(best)
      _ambiguous -> nil
    end
  end

  defp tag_similarity(left, right) do
    left.tags
    |> normalized_tags()
    |> MapSet.intersection(normalized_tags(right.tags))
    |> MapSet.size()
  end

  defp normalized_tags(tags) do
    tags
    |> Enum.map(&String.downcase(String.trim(&1)))
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp language_order(by_language) do
    present = Map.keys(by_language)
    config = Config.get()

    preferred =
      [config.default_language | config.supported_languages]
      |> Enum.uniq()
      |> Enum.filter(&(&1 in present))

    preferred ++ Enum.sort(present -- preferred)
  end

  defp sort_group(group), do: Enum.sort_by(group, &article_order/1)
  defp sort_articles(articles), do: Enum.sort_by(articles, &article_order/1)

  defp article_order(article) do
    language_index =
      Config.get().supported_languages
      |> Enum.find_index(&(&1 == article.lang))

    {language_index || length(Config.get().supported_languages), article.lang, article.slug,
     article.path}
  end
end
