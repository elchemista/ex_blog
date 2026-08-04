defmodule ExBlog.Agent.Presenter do
  @moduledoc false

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
    Classifier: #{models.classifier}
    Embedding model: #{Map.get(models, :embedding, "not configured")}

    GitHub token: #{configured(config.github_token)}
    OpenRouter token: #{configured(config.openrouter_token)}
    """
    |> String.trim()
  end

  def present(%{articles: articles, count: count}) when is_list(articles) do
    rows =
      Enum.map_join(articles, "\n", fn article ->
        "- [#{article.lang}] #{article.title} (#{article.slug}, #{article.status})"
      end)

    if rows == "", do: "No articles found.", else: "#{count} articles:\n#{rows}"
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

  def present(%{title: title, slug: slug, lang: lang, status: status} = article) do
    base = "#{title}\n#{lang}/#{slug} · #{status}"

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
