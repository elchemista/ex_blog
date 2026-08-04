defmodule ExBlog.Agent do
  @moduledoc """
  English-first Spectre editorial agent.

  English is the operational language for prompts and visible replies. Article
  generation and translation still obey the target language captured by the
  editorial flow. Business rules remain in `ExBlog.Agent.Actions`.
  """

  use Spectre.Agent,
    stack: ExBlog.AI,
    prompt_root: "lib/ex_blog_web/prompts",
    input_timeout: 30_000

  alias ExBlog.Agent.RouterPipeline
  alias ExBlog.Agent.Skills.Editorial
  alias ExBlog.Agent.Skills.Operations
  alias ExBlog.Agent.Skills.Reader
  alias ExBlog.AI.OpenRouter
  alias ExBlogWeb.Prompt

  require Editorial
  require Operations
  require Reader

  classifier(OpenRouter,
    model: "ex-blog/runtime-fast",
    prompt: &Prompt.classifier/1,
    llm_opts: [temperature: 0.0, max_tokens: 16]
  )

  state(ExBlog.Agent.StateStore)
  memory(ExBlog.Agent.Memory)

  router(
    pipeline: RouterPipeline,
    via: [:regex, :semantic_cache, :llm_classifier],
    terminal_labels: [
      :UNSAFE,
      :CANCEL_ARTICLE_CREATION,
      :ATTACH_ARTICLE_IMAGE,
      :LIST_ARTICLES,
      :READ_ARTICLE,
      :SEARCH_ARTICLES,
      :CHECK_BLOG_PAGE,
      :SHOW_BLOG_CONFIG,
      :SHOW_AI_BUDGET,
      :CHECK_OPENROUTER,
      :SYNC_BLOG_REPOSITORY,
      :START_ARTICLE_CREATION,
      :CAPTURE_ARTICLE_TITLE,
      :CAPTURE_ARTICLE_CATEGORY,
      :CAPTURE_ARTICLE_LANGUAGE,
      :CAPTURE_ARTICLE_BRIEF,
      :CAPTURE_ARTICLE_SEO,
      :REVISE_ARTICLE,
      :TRANSLATE_ARTICLE,
      :GENERATE_ARTICLE_SEO,
      :PUBLISH_ARTICLE,
      :UNPUBLISH_ARTICLE,
      :DELETE_ARTICLE,
      :UNKNOWN
    ],
    semantic_cache?: true,
    semantic_cache: ExBlog.Agent.SemanticCache,
    embedding: {ExBlog.AI.Embedding, []},
    semantic_learn?: true,
    semantic_learn_min_chars: 8,
    semantic_learn_max_chars: 1_000,
    classification_log?: false
  )

  input_pipeline do
    plug(Spectre.Input.Plugs.NormalizeText, trim?: true)
    plug(ExBlog.Agent.Plugs.RedactSecrets)
  end

  action_provider(:local, ExBlog.Agent.Actions.Provider,
    modes: [
      list_articles: :read,
      read_article: :read,
      search_articles: :read,
      show_config: :read,
      openrouter_status: :read,
      budget_status: :read,
      check_page: :read,
      create_article: :write,
      revise_article: :write,
      translate_article: :write,
      generate_seo: :write,
      publish_article: :write,
      unpublish_article: :write,
      delete_article: :destructive,
      sync_repository: :write
    ]
  )

  skill(Reader,
    as: :reader,
    bind: [
      list_articles: :list_articles,
      read_article: :read_article,
      search_articles: :search_articles,
      check_page: :check_page
    ]
  )

  skill(Editorial,
    as: :editorial,
    bind: [
      create_article: :create_article,
      revise_article: :revise_article,
      translate_article: :translate_article,
      generate_seo: :generate_seo,
      publish_article: :publish_article,
      unpublish_article: :unpublish_article,
      delete_article: :delete_article
    ]
  )

  skill(Operations,
    as: :operations,
    bind: [
      show_config: :show_config,
      openrouter_status: :openrouter_status,
      budget_status: :budget_status,
      sync_repository: :sync_repository
    ]
  )

  interrupt :UNSAFE,
    regex: ~r/ignore.*instructions|show.*(?:token|secret)|system\s+prompt/iu,
    via: [:regex],
    cache: false do
    reply(:unsafe_request)
  end

  flow :fallback do
    on :UNKNOWN do
      reply(:unknown_request)
    end
  end
end
