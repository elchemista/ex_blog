defmodule ExBlog.Agent.Skills.Reader do
  @moduledoc """
  Read-only blog discovery and public-page verification capability.

  Every intent deliberately declares the complete routing matrix:

    * `regex` is reserved for explicit, deterministic slash commands;
    * `embedding` supplies semantic examples to the optional static matcher,
      the classifier route tree, and Spectre's static exact-cache rows;
    * `classifier` uses ExBlog's trained local model before any remote model;
    * `semantic_cache` can reuse a verified vector learned from an earlier LLM
      classification;
    * `llm_classifier` handles a novel paraphrase when cheaper evidence misses.

  `regex_strength: :hard` applies only to an actual regex candidate. Embedding
  candidates remain threshold-gated. These routes are safe to mark `learn:
  true` because every handler is read-only and cannot mutate the Git checkout.
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
        regex: ~r/^\/articles(?:\s|$)/u,
        embedding: [
          "list the blog articles",
          "show every blog post",
          "give me an inventory of the article archive"
        ],
        regex_strength: :hard,
        learn: true,
        via: [:regex, :embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:list_articles, args: %{})
      end

      on :READ_ARTICLE,
        regex: ~r/^\/read(?:\s|$)/u,
        embedding: [
          "read a complete article",
          "show one specific blog post",
          "open the full Markdown content for this slug"
        ],
        regex_strength: :hard,
        learn: true,
        via: [:regex, :embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:read_article, args: %{})
      end

      on :SEARCH_ARTICLES,
        regex: ~r/^\/search(?:\s|$)/u,
        embedding: [
          "search the article archive",
          "find blog posts about a topic",
          "locate content that discusses a subject"
        ],
        regex_strength: :hard,
        learn: true,
        via: [:regex, :embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:search_articles, args: %{})
      end
    end

    flow :quality do
      on :CHECK_BLOG_PAGE,
        regex: ~r/^\/check(?:\s|$)/u,
        embedding: [
          "audit a public blog page",
          "check an article page for SEO problems",
          "inspect the rendered page structure and metadata"
        ],
        regex_strength: :hard,
        learn: true,
        via: [:regex, :embedding, :classifier, :semantic_cache, :llm_classifier] do
        action(:check_page, args: %{})
      end
    end
  end
end
