defmodule ExBlog.Content.Article do
  @moduledoc """
  Canonical in-memory representation of a Markdown article.
  """

  @enforce_keys [:path, :slug, :lang, :status, :body, :html, :checksum]
  defstruct [
    :path,
    :title,
    :slug,
    :lang,
    :status,
    :date,
    :updated,
    :category,
    :seo_title,
    :seo_description,
    :cover,
    :cover_alt,
    :translation_of,
    :body,
    :html,
    :excerpt,
    :checksum,
    tags: [],
    valid?: true,
    errors: []
  ]

  @type status :: :draft | :published | :invalid

  @type t :: %__MODULE__{
          path: String.t(),
          title: String.t() | nil,
          slug: String.t(),
          lang: String.t(),
          status: status(),
          date: Date.t() | nil,
          updated: Date.t() | nil,
          category: String.t() | nil,
          tags: [String.t()],
          seo_title: String.t() | nil,
          seo_description: String.t() | nil,
          cover: String.t() | nil,
          cover_alt: String.t() | nil,
          translation_of: String.t() | nil,
          body: String.t(),
          html: String.t(),
          excerpt: String.t() | nil,
          checksum: String.t(),
          valid?: boolean(),
          errors: [String.t()]
        }

  @spec key(t()) :: {String.t(), String.t()} | {:invalid, String.t()}
  def key(%__MODULE__{valid?: true} = article), do: {article.lang, article.slug}
  def key(%__MODULE__{path: path}), do: {:invalid, path}

  @spec published?(t()) :: boolean()
  def published?(%__MODULE__{valid?: true, status: :published}), do: true
  def published?(%__MODULE__{}), do: false

  @spec invalid(String.t(), term()) :: t()
  def invalid(path, reason) do
    message = format_reason(reason)

    %__MODULE__{
      path: path,
      slug: Path.basename(path, Path.extname(path)),
      lang: "und",
      status: :invalid,
      body: "",
      html: "",
      checksum: checksum(message),
      valid?: false,
      errors: [message]
    }
  end

  @spec checksum(String.t()) :: String.t()
  def checksum(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason, limit: 20, printable_limit: 500)
end
