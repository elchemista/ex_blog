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
        regex: [~r/^\/articles(?:\s|$)/iu, ~r/^(?:lista|elenca).*(?:articoli|post)/iu] do
        action(:list_articles, args: %{})
      end

      on :READ_ARTICLE,
        regex: [~r/^\/read(?:\s|$)/iu, ~r/^(?:leggi|mostra).*(?:articolo|post)/iu] do
        action(:read_article, args: %{})
      end

      on :SEARCH_ARTICLES,
        regex: [~r/^\/search(?:\s|$)/iu, ~r/^(?:cerca|trova).*(?:articoli|post)/iu] do
        action(:search_articles, args: %{})
      end
    end

    flow :quality do
      on :CHECK_BLOG_PAGE,
        regex: [
          ~r/^\/check(?:\s|$)/iu,
          ~r/^(?:controlla|verifica|ispeziona|analizza)(?:\s+(?:la\s+)?(?:pagina|sito|blog)|\s+https?:\/\/)/iu,
          ~r/^(?:check|verify|inspect|audit)(?:\s+(?:the\s+)?(?:page|site|blog)|\s+https?:\/\/)/iu
        ] do
        action(:check_page, args: %{})
      end
    end
  end
end
