defmodule ExBlogWeb.Canonical do
  @moduledoc """
  One place that decides which URL is the canonical one for a public page.

  `/` and `/<default language>` render the same page, so exactly one of them may
  be advertised — in the `canonical` tag, in the sitemap, and in the `hreflang`
  set. Letting each caller decide that separately is how a canonical tag ends up
  disagreeing with the sitemap, and a search engine that cannot tell which of two
  identical URLs is the real one may index neither.

  `/` wins: it is the address people link to and type, so it is where the site's
  authority collects.
  """

  alias ExBlog.Config

  @doc "Path of the article index for one language. The default language lives at `/`."
  @spec index_path(String.t(), Config.t()) :: String.t()
  def index_path(language, config \\ Config.get()) do
    if language == config.default_language, do: "/", else: "/#{language}"
  end

  @doc "Absolute URL of the article index for one language."
  @spec index_url(String.t(), Config.t()) :: String.t()
  def index_url(language, config \\ Config.get()),
    do: Config.canonical_url(config) <> index_path(language, config)

  @doc """
  `hreflang` set for the article index.

  Includes the page itself — a self-referencing `hreflang` is required for the set
  to be valid — and an `x-default` naming the URL a visitor gets when none of the
  declared languages match.
  """
  @spec index_alternates(Config.t()) :: [%{hreflang: String.t(), url: String.t()}]
  def index_alternates(config \\ Config.get()) do
    config.supported_languages
    |> Enum.map(&%{hreflang: &1, url: index_url(&1, config)})
    |> Kernel.++([%{hreflang: "x-default", url: index_url(config.default_language, config)}])
  end

  @doc "`hreflang` set for a path that exists under every language prefix."
  @spec localized_alternates((String.t() -> String.t()), Config.t()) :: [
          %{hreflang: String.t(), url: String.t()}
        ]
  def localized_alternates(path_builder, config \\ Config.get())
      when is_function(path_builder, 1) do
    site_url = Config.canonical_url(config)

    config.supported_languages
    |> Enum.map(&%{hreflang: &1, url: site_url <> path_builder.(&1)})
    |> Kernel.++([
      %{hreflang: "x-default", url: site_url <> path_builder.(config.default_language)}
    ])
  end
end
