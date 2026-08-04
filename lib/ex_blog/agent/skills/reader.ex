defmodule ExBlog.Agent.Skills.Reader do
  @moduledoc """
  Read-only blog discovery and public-page verification capability.
  """

  use Spectre.Skill, id: :reader, version: 1

  requires_action(:list_articles, mode: :read)
  requires_action(:read_article, mode: :read)
  requires_action(:search_articles, mode: :read)
  requires_action(:check_page, mode: :read)

  flow :blog do
    flow :articles do
      on :LIST_ARTICLES,
        regex: [
          ~r/^\/articles(?:\s|$)/iu,
          ~r/^(?:list|show)(?:\s+me)?(?:\s+(?:all|every|the))?.*(?:articles|posts)\b/iu
        ],
        embedding: ["list the blog articles", "show every blog post"],
        learn: true do
        action(:list_articles, args: %{})
      end

      on :READ_ARTICLE,
        regex: [
          ~r/^\/read(?:\s|$)/iu,
          ~r/^(?:read|show)(?:\s+me)?.*(?:article|post)\b/iu
        ],
        embedding: ["read a complete article", "show one blog post"],
        learn: true do
        action(:read_article, args: %{})
      end

      on :SEARCH_ARTICLES,
        regex: [
          ~r/^\/search(?:\s|$)/iu,
          ~r/^(?:search|find).*(?:articles|posts)\b/iu
        ],
        embedding: ["search the article archive", "find blog posts about a topic"],
        learn: true do
        action(:search_articles, args: %{})
      end
    end

    flow :quality do
      on :CHECK_BLOG_PAGE,
        regex: [
          ~r/^\/check(?:\s|$)/iu,
          ~r/^(?:check|verify|inspect|audit)(?:\s+(?:the\s+)?(?:page|site|blog)|\s+https?:\/\/)/iu
        ],
        embedding: ["audit a public blog page", "check an article page for SEO problems"],
        learn: true do
        action(:check_page, args: %{})
      end
    end
  end
end
