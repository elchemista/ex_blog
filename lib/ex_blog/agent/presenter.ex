defmodule ExBlog.Agent.Presenter do
  @moduledoc """
  Converts typed action results into bounded, administrator-facing text.

  Action execution returns maps because Telegram, MCP, and tests need structured
  outcomes. Beam uses this module only at the presentation boundary. Sensitive
  configuration is already projected by `ExBlog.Config.public/0`; unexpected
  errors receive a final redaction pass before they become visible text.

  Pattern order is intentional: specific result shapes are rendered first and
  the JSON/inspection clauses are a safe fallback for new read-only actions.
  """

  @doc "Renders a known action result or failure as concise English text."
  @spec present(term()) :: String.t()
  def present({:ok, value}), do: present(value)
  def present({:error, reason}), do: "Operation failed: #{reason_text(reason)}"

  def present(
        %{
          repository: repository,
          branch: branch,
          default_language: default_language,
          supported_languages: languages,
          models: models
        } = config
      ) do
    agent_language = Map.get(config, :agent_language, "en")

    """
    Repository: #{repository}
    Branch: #{branch}
    Agent language: #{agent_language}
    Default article language: #{default_language}
    Supported article languages: #{Enum.join(languages, ", ")}

    Fast model: #{models.fast}
    Balanced model: #{models.balanced}
    Deep model: #{models.deep}
    Kinetic planner LLM fallback: #{display_model(Map.get(models, :kinetic_planner))}
    Kinetic planner provider failover: #{display_models(Map.get(models, :kinetic_planner_fallbacks, []))}
    Routing embedding: #{Map.get(models, :routing_embedding, "not configured")}
    Local classifier: #{Map.get(models, :local_classifier, "not configured")}
    Remote classifier fallback: #{models.classifier}
    OpenRouter embedding model: #{Map.get(models, :embedding, "not configured")}

    GitHub token: #{configured(config.github_token)}
    OpenRouter token: #{configured(config.openrouter_token)}
    """
    |> String.trim()
  end

  def present(%{articles: articles, count: count} = result) when is_list(articles) do
    rows =
      articles
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {article, number} ->
        link = article.public_url || article.source_url
        "#{number}. [#{article.lang}] #{article.title} (#{article.status})\n   #{link}"
      end)

    if rows == "" do
      "No articles found."
    else
      shown_count = Map.get(result, :shown_count, length(articles))

      truncation =
        if shown_count < count,
          do: "\n\nShowing the first #{shown_count} of #{count} articles.",
          else: ""

      """
      #{count} articles:
      #{rows}#{truncation}

      Select one by number, for example “edit article 2” or “publish article 2”.
      You can also use its exact title, `lang/slug`, public link, or Git link.
      """
      |> String.trim()
    end
  end

  def present(%{
        system_status: true,
        application: application,
        public_url: public_url,
        content: content,
        telegram: telegram,
        openrouter: openrouter,
        budget: budget
      }) do
    openrouter_status =
      cond do
        openrouter.reachable && openrouter.models_available -> "reachable; all models available"
        openrouter.reachable -> "reachable; one or more configured models unavailable"
        true -> "unreachable (#{Map.get(openrouter, :reason, :unavailable)})"
      end

    telegram_status =
      "#{telegram.connection_status} (authorization: #{telegram.auth_state}, " <>
        "last error: #{yes_no(telegram.last_error?)})"

    """
    System status
    Application: #{application.status}
    Public URL: #{public_url}
    Content index: #{content.status}; #{content.indexed_articles} articles in #{Enum.join(content.languages, ", ")}
    Telegram: #{telegram_status}
    OpenRouter: #{openrouter_status}
    AI spent this month: €#{budget.spent_month_eur}
    AI budget remaining: €#{budget.remaining_eur}
    """
    |> String.trim()
  end

  def present(%{
        period: period,
        spent_today_eur: today,
        spent_month_eur: month,
        remaining_eur: remaining,
        monthly_budget_eur: budget
      }) do
    """
    Budget: #{period}
    Spent today: €#{today}
    Spent this month: €#{month}
    Monthly budget: €#{budget}
    Remaining: €#{remaining}
    """
    |> String.trim()
  end

  def present(%{
        ecosystem_status: true,
        status: status,
        summary: summary,
        libraries: libraries,
        fetched_at: fetched_at
      }) do
    rows =
      Enum.map_join(libraries, "\n", fn library ->
        version = if library.version, do: " #{library.version}", else: ""
        "- #{library.name}: #{library.status}#{version} (#{library.source})"
      end)

    """
    Ecosystem statuses synchronized and the home page snapshot was updated.
    Overall status: #{status}
    Libraries: #{summary.total}; passing: #{summary.passing}; failing: #{summary.failing}
    Refreshed: #{format_datetime(fetched_at)}
    #{rows}
    """
    |> String.trim()
  end

  def present(%{
        operation: :created,
        title: title,
        slug: slug,
        lang: lang,
        source_url: source_url
      }) do
    """
    Draft created and synchronized with Git.
    Title: #{title}
    Article: #{lang}/#{slug}
    Draft source: #{source_url}
    Status: draft — it is not public and is not included in the sitemap yet.
    """
    |> String.trim()
  end

  def present(%{
        operation: :published,
        title: title,
        public_url: public_url,
        source_url: source_url
      }) do
    """
    Article published: #{title}
    Public link: #{public_url}
    Git source: #{source_url}
    The public index, feeds, and sitemap now read it from the synchronized content index.
    """
    |> String.trim()
  end

  def present(%{
        operation: :unpublished,
        title: title,
        lang: lang,
        slug: slug,
        source_url: source_url
      }) do
    """
    Article returned to draft: #{title}
    Article: #{lang}/#{slug}
    Draft source: #{source_url}
    It is no longer public or included in the sitemap.
    """
    |> String.trim()
  end

  def present(
        %{
          operation: :revised,
          title: title,
          lang: lang,
          slug: slug,
          status: status,
          source_url: source_url
        } = article
      ) do
    link = article.public_url || source_url

    """
    Article updated: #{title}
    Article: #{lang}/#{slug} · #{status}
    Link: #{link}
    The approved Markdown revision was synchronized with Git.
    """
    |> String.trim()
  end

  def present(%{title: title, slug: slug, lang: lang, status: status} = article) do
    link = article.public_url || article.source_url
    base = "#{title}\n#{lang}/#{slug} · #{status}\n#{link}"

    case Map.get(article, :body) do
      body when is_binary(body) -> base <> "\n\n" <> body
      _other -> base
    end
  end

  def present(%{diff: diff, proposed_body: _body}) do
    "The revision is ready. Confirm it by applying the proposed_body below.\n\n#{diff}"
  end

  def present(%{deleted: true, lang: lang, slug: slug}),
    do: "Article deleted: #{lang}/#{slug}."

  def present(%{total: total, invalid: invalid, commit: commit, rebuilt_at: rebuilt_at}) do
    """
    Repository synchronized.
    Commit: #{commit}
    Indexed articles: #{total}
    Invalid article files: #{invalid}
    Index rebuilt: #{format_datetime(rebuilt_at)}
    """
    |> String.trim()
  end

  def present(%{configured: true, reachable: true, models_available: available}) do
    suffix =
      if available,
        do: "all configured models are available",
        else: "some configured models are unavailable"

    "OpenRouter is configured and reachable; #{suffix}."
  end

  def present(%{
        url: url,
        title: title,
        baseline_ok?: baseline_ok?,
        issues: issues,
        warnings: warnings,
        assessment: assessment
      }) do
    status = if baseline_ok?, do: "passed", else: "issues detected"

    details =
      [
        formatted_findings("Issues", issues),
        formatted_findings("Warnings", warnings)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    [
      "Page audit: #{title || "untitled"}",
      url,
      "Technical checks: #{status}",
      details,
      assessment
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  def present(value) when is_binary(value), do: value
  def present(value) when is_atom(value), do: Atom.to_string(value)

  def present(value) when is_map(value) or is_list(value) do
    case Jason.encode(value, pretty: true) do
      {:ok, json} -> json
      {:error, _reason} -> inspect(value, limit: 50, printable_limit: 8_000)
    end
  end

  def present(value), do: inspect(value, limit: 50, printable_limit: 8_000)

  defp configured(:configured), do: "configured"
  defp configured(_other), do: "not configured"

  defp display_model(model) when is_binary(model) and model != "", do: model
  defp display_model(_model), do: "not configured"

  defp display_models(models) when is_list(models) and models != [], do: Enum.join(models, ", ")
  defp display_models(_models), do: "not configured"

  defp yes_no(true), do: "yes"
  defp yes_no(false), do: "no"

  defp format_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_datetime(value), do: to_string(value)

  defp formatted_findings(_label, []), do: nil

  defp formatted_findings(label, findings) do
    rows = Enum.map_join(findings, "\n", &("- " <> &1))
    "#{label}:\n#{rows}"
  end

  defp reason_text(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp reason_text(reason) do
    reason
    |> inspect(limit: 20, printable_limit: 2_000)
    |> ExBlog.Config.redact()
  end
end
