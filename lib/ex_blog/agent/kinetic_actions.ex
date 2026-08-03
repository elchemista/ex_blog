defmodule ExBlog.Agent.KineticActions do
  @moduledoc """
  Typed Action Language catalog for the editorial agent.

  These functions describe the operations available to Spectre Kinetic. The
  context-aware implementation remains in `ExBlog.Agent.Actions` and is only
  called by the registered Spectre provider after policy checks.
  """

  use SpectreKinetic

  alias ExBlog.Config

  @al ~s(LIST ARTICLES)
  @doc """
  List blog articles without returning their Markdown bodies.

  AL: LIST ARTICLES
  AL: SHOW BLOG POSTS
  AL: ELENCA ARTICOLI
  """
  @spec list_articles() :: {:ok, map()}
  def list_articles, do: {:ok, %{}}

  @al ~s(READ ARTICLE LANG="it" SLUG="phoenix-liveview")
  @doc """
  Read one complete article, including its Markdown body.

  AL: READ ARTICLE LANG="en" SLUG="spectre-agents"
  AL: SHOW ARTICLE LANG="it" SLUG="phoenix-liveview"
  AL: LEGGI ARTICOLO LANG="it" SLUG="phoenix-liveview"
  """
  @spec read_article(lang :: String.t(), slug :: String.t()) :: {:ok, map()}
  def read_article(lang, slug), do: {:ok, %{lang: lang, slug: slug}}

  @al ~s(SEARCH ARTICLES QUERY="Phoenix LiveView")
  @doc """
  Search article titles, categories, tags, and Markdown content.

  AL: SEARCH ARTICLES QUERY="Spectre Kinetic"
  AL: FIND BLOG POSTS QUERY="Telegram"
  AL: CERCA ARTICOLI QUERY="Phoenix"
  """
  @spec search_articles(query :: String.t()) :: {:ok, map()}
  def search_articles(query), do: {:ok, %{query: query}}

  @al ~s(SHOW BLOG CONFIG)
  @doc """
  Show the safe blog configuration without credential values.

  AL: SHOW BLOG CONFIG
  AL: MOSTRA CONFIGURAZIONE BLOG
  """
  @spec show_config() :: {:ok, map()}
  def show_config, do: {:ok, %{}}

  @al ~s(CHECK OPENROUTER STATUS)
  @doc """
  Check OpenRouter reachability and configured model availability.

  AL: CHECK OPENROUTER STATUS
  AL: VERIFICA OPENROUTER
  """
  @spec openrouter_status() :: {:ok, map()}
  def openrouter_status, do: {:ok, %{}}

  @al ~s(SHOW AI BUDGET)
  @doc """
  Show the current daily and monthly AI spend.

  AL: SHOW AI BUDGET
  AL: MOSTRA BUDGET AI
  """
  @spec budget_status() :: {:ok, map()}
  def budget_status, do: {:ok, %{}}

  @al ~s(CHECK BLOG PAGE URL="https://example.com/articles/example")
  @doc """
  Inspect one rendered public blog page with Spectre Lens.

  AL: CHECK BLOG PAGE URL="https://example.com/articles/example"
  AL: AUDIT ARTICLE PAGE URL="https://example.com/articles/example"
  AL: CONTROLLA PAGINA BLOG URL="https://example.com/articles/example"
  """
  @spec check_page(url :: String.t()) :: {:ok, map()}
  def check_page(url), do: {:ok, %{url: url}}

  @al ~s(CREATE ARTICLE TITLE="Phoenix and Spectre Kinetic" LANG="it" CATEGORY="Tecnologia" BRIEF="Explain the architecture")
  @doc """
  Generate and commit a new draft article.

  AL: CREATE ARTICLE TITLE="Building an editorial agent" LANG="en" CATEGORY="AI" BRIEF="Explain the design and safety boundaries"
  AL: WRITE BLOG POST TITLE="Safe Git automation" LANG="en" CATEGORY="Engineering" BRIEF="Show a practical workflow"
  AL: CREA ARTICOLO TITLE="Phoenix LiveView in produzione" LANG="it" CATEGORY="Elixir" BRIEF="Spiega architettura e deploy"
  """
  @spec create_article(
          title :: String.t(),
          lang :: String.t(),
          category :: String.t(),
          brief :: String.t()
        ) :: {:ok, map()}
  def create_article(title, lang, category, brief) do
    {:ok, %{title: title, lang: lang, category: category, brief: brief}}
  end

  @al ~s(REVISE ARTICLE LANG="it" SLUG="phoenix-liveview" INSTRUCTIONS="Improve the introduction")
  @doc """
  Generate a revision proposal for an existing article.

  AL: REVISE ARTICLE LANG="en" SLUG="spectre-agents" INSTRUCTIONS="Add a deployment section"
  AL: EDIT ARTICLE LANG="it" SLUG="phoenix-liveview" INSTRUCTIONS="Correggi i refusi"
  AL: REVISIONA ARTICOLO LANG="it" SLUG="phoenix-liveview" INSTRUCTIONS="Rendi il testo più chiaro"
  """
  @spec revise_article(lang :: String.t(), slug :: String.t(), instructions :: String.t()) ::
          {:ok, map()}
  def revise_article(lang, slug, instructions),
    do: {:ok, %{lang: lang, slug: slug, instructions: instructions}}

  @al ~s(TRANSLATE ARTICLE LANG="it" SLUG="phoenix-liveview" TARGET_LANG="en")
  @doc """
  Translate an article and commit the translation as a draft.

  AL: TRANSLATE ARTICLE LANG="en" SLUG="spectre-agents" TARGET_LANG="it"
  AL: TRADUCI ARTICOLO LANG="it" SLUG="phoenix-liveview" TARGET_LANG="en"
  """
  @spec translate_article(
          lang :: String.t(),
          slug :: String.t(),
          target_lang :: String.t()
        ) :: {:ok, map()}
  def translate_article(lang, slug, target_lang),
    do: {:ok, %{lang: lang, slug: slug, target_lang: target_lang}}

  @al ~s(GENERATE ARTICLE SEO LANG="it" SLUG="phoenix-liveview")
  @doc """
  Generate and commit SEO metadata for an existing article.

  AL: GENERATE ARTICLE SEO LANG="en" SLUG="spectre-agents"
  AL: CREA SEO ARTICOLO LANG="it" SLUG="phoenix-liveview"
  """
  @spec generate_seo(lang :: String.t(), slug :: String.t()) :: {:ok, map()}
  def generate_seo(lang, slug), do: {:ok, %{lang: lang, slug: slug}}

  @al ~s(PUBLISH ARTICLE LANG="it" SLUG="phoenix-liveview")
  @doc """
  Publish an existing draft article.

  AL: PUBLISH ARTICLE LANG="en" SLUG="spectre-agents"
  AL: PUBBLICA ARTICOLO LANG="it" SLUG="phoenix-liveview"
  """
  @spec publish_article(lang :: String.t(), slug :: String.t()) :: {:ok, map()}
  def publish_article(lang, slug), do: {:ok, %{lang: lang, slug: slug}}

  @al ~s(UNPUBLISH ARTICLE LANG="it" SLUG="phoenix-liveview")
  @doc """
  Return a published article to draft status.

  AL: UNPUBLISH ARTICLE LANG="en" SLUG="spectre-agents"
  AL: RITIRA ARTICOLO LANG="it" SLUG="phoenix-liveview"
  """
  @spec unpublish_article(lang :: String.t(), slug :: String.t()) :: {:ok, map()}
  def unpublish_article(lang, slug), do: {:ok, %{lang: lang, slug: slug}}

  @al ~s(DELETE ARTICLE LANG="it" SLUG="phoenix-liveview")
  @doc """
  Delete an article from the Git repository.

  AL: DELETE ARTICLE LANG="en" SLUG="spectre-agents"
  AL: ELIMINA ARTICOLO LANG="it" SLUG="phoenix-liveview"
  """
  @spec delete_article(lang :: String.t(), slug :: String.t()) :: {:ok, map()}
  def delete_article(lang, slug), do: {:ok, %{lang: lang, slug: slug}}

  @al ~s(SYNC BLOG REPOSITORY)
  @doc """
  Fetch the configured Git branch and rebuild the content index.

  AL: SYNC BLOG REPOSITORY
  AL: UPDATE BLOG REPOSITORY
  AL: SINCRONIZZA REPOSITORY BLOG
  """
  @spec sync_repository() :: {:ok, map()}
  def sync_repository, do: {:ok, %{}}

  @doc """
  Builds the canonical Action Language instruction for a completed article
  intake. Values are redacted, bounded, and quoted as inert AL data.
  """
  @spec create_article_command(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def create_article_command(title, lang, category, brief) do
    ~s(CREATE ARTICLE TITLE="#{al_value(title, 160)}" LANG="#{al_value(lang, 32)}" CATEGORY="#{al_value(category, 80)}" BRIEF="#{al_value(brief, 8_000)}")
  end

  @spec al_value(String.t(), pos_integer()) :: String.t()
  defp al_value(value, limit) do
    value
    |> Config.redact()
    |> String.slice(0, limit)
    |> String.replace(~r/\s+/u, " ")
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end
end
