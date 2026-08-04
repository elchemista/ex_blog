defmodule ExBlog.Agent.ArticleSelector do
  @moduledoc """
  Resolves an administrator-facing article reference without an LLM.

  Supported references are a number from the latest displayed list, a
  `lang/slug` identifier, a public or Git link, a bare slug, and an exact or
  uniquely mentioned title. Every successful result comes from the current
  content index.
  """

  alias ExBlog.Agent.ArticleSelections
  alias ExBlog.Config
  alias ExBlog.Content
  alias ExBlog.Content.Article

  @type error_reason ::
          :article_list_required
          | :article_not_found
          | :stale_article_selection
          | {:article_number_out_of_range, term()}
          | {:ambiguous_article, [Article.t()]}

  @doc "Resolves one article reference from natural command text."
  @spec resolve(String.t(), keyword()) :: {:ok, Article.t()} | {:error, error_reason()}
  def resolve(text, opts \\ [])

  def resolve(text, opts) when is_binary(text) and is_list(opts) do
    case selection_number(text) do
      nil -> resolve_reference(text)
      number -> resolve_number(number, Keyword.get(opts, :conversation_id))
    end
  end

  def resolve(_text, _opts), do: {:error, :article_not_found}

  @doc "Returns the explicit one-based list number in an article command."
  @spec selection_number(String.t()) :: pos_integer() | nil
  def selection_number(text) when is_binary(text) do
    patterns = [
      ~r/(?:^|\s)#(?<number>\d{1,4})(?:\s|$)/u,
      ~r/(?:^|\s)(?:article|post)\s+#?(?<number>\d{1,4})(?:\s|$)/iu,
      ~r/^\s*(?:edit|revise|update|publish|unpublish|delete|remove|read|show|translate|seo)\s+#?(?<number>\d{1,4})(?:\s+(?:article|post))?(?:\s|[:.!?-]|$)/iu
    ]

    Enum.find_value(patterns, &captured_number(&1, text))
  end

  def selection_number(_text), do: nil

  defp resolve_number(number, conversation_id) do
    with {:ok, entry} <- ArticleSelections.fetch(conversation_id, number),
         {:ok, article} <-
           Content.get(entry.lang, entry.slug, published_only?: false) do
      {:ok, article}
    else
      {:error, :not_found} -> {:error, :stale_article_selection}
      {:error, _reason} = error -> error
    end
  end

  defp resolve_reference(text) do
    case explicit_identifier(text) do
      {:ok, lang, slug} ->
        case Content.get(lang, slug, published_only?: false) do
          {:ok, article} -> {:ok, article}
          {:error, :not_found} -> resolve_from_index(text)
        end

      :error ->
        resolve_from_index(text)
    end
  end

  defp resolve_from_index(text) do
    articles = Content.list(lang: :all, status: :all)

    scored =
      articles
      |> Enum.map(&{&1, reference_score(&1, text)})
      |> Enum.filter(fn {_article, score} -> score > 0 end)

    case scored do
      [] ->
        {:error, :article_not_found}

      scored ->
        maximum = scored |> Enum.map(&elem(&1, 1)) |> Enum.max()
        matches = for {article, ^maximum} <- scored, do: article

        case matches do
          [article] -> {:ok, article}
          articles -> {:error, {:ambiguous_article, articles}}
        end
    end
  end

  defp explicit_identifier(text) do
    languages = Config.get().supported_languages |> Enum.map_join("|", &Regex.escape/1)

    regex =
      Regex.compile!(
        "(?:^|[^\\p{L}\\p{N}-])(?<lang>#{languages})[/:](?<slug>[a-z0-9]+(?:-[a-z0-9]+)*)(?:[^\\p{L}\\p{N}-]|$)",
        "iu"
      )

    case Regex.named_captures(regex, text) do
      %{"lang" => lang, "slug" => slug} ->
        {:ok, String.downcase(lang), String.downcase(slug)}

      _missing ->
        :error
    end
  end

  defp reference_score(%Article{} = article, text) do
    input = normalize_reference(text)
    title = normalize_reference(article.title || "")
    slug = normalize_reference(article.slug)
    raw_input = String.downcase(text)

    cond do
      known_link?(article, raw_input) -> 1_000
      raw_token_present?(raw_input, article.slug) -> 900 + String.length(article.slug)
      phrase_present?(input, title) -> 700 + String.length(title)
      phrase_present?(input, slug) -> 600 + String.length(slug)
      true -> 0
    end
  end

  defp known_link?(article, raw_input) do
    links = [
      Config.public_article_url(article.lang, article.slug),
      Config.repository_file_url(article.path),
      article.path
    ]

    Enum.any?(links, fn link ->
      is_binary(link) and link != "" and String.contains?(raw_input, String.downcase(link))
    end)
  end

  defp phrase_present?(_input, ""), do: false

  defp phrase_present?(input, phrase) do
    String.contains?(" " <> input <> " ", " " <> phrase <> " ")
  end

  defp raw_token_present?(input, slug) do
    Regex.match?(
      ~r/(?:^|[^\p{L}\p{N}-])#{Regex.escape(String.downcase(slug))}(?:[^\p{L}\p{N}-]|$)/u,
      input
    )
  end

  defp normalize_reference(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end

  defp captured_number(regex, text) do
    case Regex.named_captures(regex, text) do
      %{"number" => number} ->
        case Integer.parse(number) do
          {value, ""} when value > 0 -> value
          _invalid -> nil
        end

      _missing ->
        nil
    end
  end
end
