defmodule ExBlog.Agent do
  @moduledoc """
  Spectre editorial agent. Business rules remain in `ExBlog.Agent.Actions`.
  """

  use Spectre.Agent,
    stack: ExBlog.AI,
    prompt_root: "priv/agent_prompts",
    input_timeout: 30_000

  alias ExBlog.Agent.Prompts
  alias ExBlog.AI.OpenRouter

  classifier(OpenRouter,
    model: "ex-blog/runtime-fast",
    prompt: &Prompts.classifier/1,
    llm_opts: [temperature: 0.0, max_tokens: 16]
  )

  state(ExBlog.Agent.StateStore)
  memory(ExBlog.Agent.Memory)

  router(
    via: [:regex, :llm_classifier],
    terminal_labels: [
      :LIST,
      :READ,
      :SEARCH,
      :WRITE,
      :REVISE,
      :TRANSLATE,
      :SEO,
      :PUBLISH,
      :UNPUBLISH,
      :DELETE,
      :CONFIG,
      :BUDGET,
      :SYNC,
      :OPENROUTER,
      :CHECK_PAGE,
      :UNKNOWN
    ],
    semantic_cache?: false,
    classification_log?: false
  )

  input_pipeline do
    plug(Spectre.Input.Plugs.NormalizeText, trim?: true)
    plug(ExBlog.Agent.Plugs.RedactSecrets)
  end

  actions ExBlog.Agent.Actions do
    protect(:create_article, with: :editorial_confirmation)
    protect(:publish_article, with: :editorial_confirmation)
    protect(:delete_article, with: :editorial_confirmation)
  end

  policy :editorial_confirmation do
    request(:confirm_editorial_action)
    accept(:approved, regex: ~r/^(?:s[iì]|yes|confermo)$/iu)
    reject(:rejected, regex: ~r/^(?:no|annulla|cancel)$/iu)
    otherwise(ask: :confirm_editorial_action)
    attempts(3, then: :cancel_confirmation)
  end

  interrupt :UNSAFE,
    regex:
      ~r/(?:ignore|ignora).*(?:instructions|istruzioni)|(?:show|mostra).*(?:token|secret)|system\s+prompt/iu,
    via: [:regex],
    cache: false do
    reply(:unsafe_request)
  end

  flow :editorial do
    on :LIST,
      regex: [~r/^\/articles(?:\s|$)/iu, ~r/^(?:lista|elenca).*(?:articoli|post)/iu] do
      action(:list_articles, args: %{})
    end

    on :READ, regex: [~r/^\/read(?:\s|$)/iu, ~r/^(?:leggi|mostra).*(?:articolo|post)/iu] do
      action(:read_article, args: %{})
    end

    on :SEARCH, regex: [~r/^\/search(?:\s|$)/iu, ~r/^(?:cerca|trova).*(?:articoli|post)/iu] do
      action(:search_articles, args: %{})
    end

    on :CONFIG,
      regex: [~r/^\/config$/iu, ~r/(?:mostra|fammi vedere).*(?:configurazione|config)/iu] do
      action(:show_config, args: %{})
    end

    on :BUDGET, regex: [~r/^\/budget$/iu, ~r/(?:budget|quanto ho speso|costi?)/iu] do
      action(:budget_status, args: %{})
    end

    on :SYNC, regex: [~r/^\/sync$/iu, ~r/(?:sincronizza|aggiorna).*(?:repository|repo)/iu] do
      action(:sync_repository, args: %{})
    end

    on :OPENROUTER, regex: ~r/openrouter.*(?:configurato|funziona|status)/iu do
      action(:openrouter_status, args: %{})
    end

    on :CHECK_PAGE,
      regex: [
        ~r/^\/check(?:\s|$)/iu,
        ~r/^(?:controlla|verifica|ispeziona|analizza)(?:\s+(?:la\s+)?(?:pagina|sito|blog)|\s+https?:\/\/)/iu,
        ~r/^(?:check|verify|inspect|audit)(?:\s+(?:the\s+)?(?:page|site|blog)|\s+https?:\/\/)/iu
      ] do
      action(:check_page, args: %{})
    end

    on :WRITE, regex: ~r/^(?:\/create|scrivi|crea).*(?:articolo|post)?/iu do
      action(:create_article, args: %{})
    end

    on :REVISE, regex: ~r/^(?:\/revise|rivedi|revisiona|riscrivi)/iu do
      action(:revise_article, args: %{})
    end

    on :TRANSLATE, regex: ~r/^(?:\/translate|traduci)/iu do
      action(:translate_article, args: %{})
    end

    on :SEO, regex: ~r/^(?:\/seo|genera.*seo)/iu do
      action(:generate_seo, args: %{})
    end

    on :PUBLISH, regex: ~r/^(?:\/publish|pubblica)/iu do
      action(:publish_article, args: %{})
    end

    on :UNPUBLISH, regex: ~r/^(?:\/unpublish|ritira|depubblica)/iu do
      action(:unpublish_article, args: %{})
    end

    on :DELETE, regex: ~r/^(?:\/delete|elimina|cancella).*(?:articolo|post)?/iu do
      action(:delete_article, args: %{})
    end

    on :UNKNOWN do
      reply(:unknown_request)
    end
  end

  def cancel_confirmation(_input, _ctx), do: "Operazione annullata: conferma non ricevuta."
end
