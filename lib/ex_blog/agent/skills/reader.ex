defmodule ExBlog.Agent.Skills.Reader do
  @moduledoc """
  Read-only blog discovery and public-page verification capability.

  Every intent deliberately declares the complete routing matrix:

    * `embedding` supplies semantic examples to the optional static matcher,
      the classifier route tree, and Spectre's static exact-cache rows;
    * `classifier` uses ExBlog's optional local model when the environment
      enables it;
    * `semantic_cache` can reuse a verified vector learned from an earlier LLM
      classification;
    * `llm_classifier` handles a novel paraphrase when cheaper evidence misses.

  There are no bot-style slash commands: the administrator writes plain
  English and routing is entirely language-based. These routes are safe to
  mark `learn: true` because every handler is read-only and cannot mutate the
  Git checkout.
  """

  use Spectre.Skill, id: :reader, version: 1

  requires_action(:list_articles, mode: :read)
  requires_action(:read_article, mode: :read)
  requires_action(:search_articles, mode: :read)
  requires_action(:check_page, mode: :read)

  # Flow nesting is descriptive here: it gives the classifier an intelligible
  # route tree (`blog/articles` and `blog/quality`) without creating a multi-turn
  # cursor. The editorial skill is the module that owns conversational cursors.
  flow :blog do
    flow :articles do
      on :LIST_ARTICLES,
        embedding: [
          "list the blog articles",
          "show every blog post",
          "give me an inventory of the article archive"
        ],
        learn: true,
        via: [:embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:list_articles, args: %{})
      end

      on :READ_ARTICLE,
        embedding: [
          "read a complete article",
          "show one specific blog post",
          "open the full Markdown content for this slug"
        ],
        learn: true,
        via: [:embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:read_article, args: %{})
      end

      on :SEARCH_ARTICLES,
        embedding: [
          "search the article archive",
          "find blog posts about a topic",
          "locate content that discusses a subject"
        ],
        learn: true,
        via: [:embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:search_articles, args: %{})
      end
    end

    flow :quality do
      on :CHECK_BLOG_PAGE,
        embedding: [
          "audit a public blog page",
          "check an article page for SEO problems",
          "inspect the rendered page structure and metadata"
        ],
        learn: true,
        via: [:embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:check_page, args: %{})
      end
    end
  end
end
