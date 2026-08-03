defmodule ExBlog.Agent.Presenter do
  @moduledoc false

  @spec present(term()) :: String.t()
  def present({:ok, value}), do: present(value)
  def present({:error, reason}), do: "Operazione non riuscita: #{reason_text(reason)}"

  def present(
        %{
          repository: repository,
          branch: branch,
          default_language: default_language,
          supported_languages: languages,
          models: models
        } = config
      ) do
    """
    Repository: #{repository}
    Branch: #{branch}
    Lingua predefinita: #{default_language}
    Lingue supportate: #{Enum.join(languages, ", ")}

    Fast model: #{models.fast}
    Balanced model: #{models.balanced}
    Deep model: #{models.deep}
    Classifier: #{models.classifier}

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

    if rows == "", do: "Nessun articolo trovato.", else: "#{count} articoli:\n#{rows}"
  end

  def present(%{
        period: period,
        spent_today_eur: today,
        spent_month_eur: month,
        remaining_eur: remaining,
        monthly_budget_eur: budget
      }) do
    """
    Budget #{period}
    Speso oggi: €#{today}
    Speso questo mese: €#{month}
    Budget mensile: €#{budget}
    Rimanente: €#{remaining}
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
    "Revisione pronta. Conferma applicando il proposed_body seguente.\n\n#{diff}"
  end

  def present(%{deleted: true, lang: lang, slug: slug}),
    do: "Articolo eliminato: #{lang}/#{slug}."

  def present(%{configured: true, reachable: true, models_available: available}) do
    suffix =
      if available,
        do: "i modelli configurati sono disponibili",
        else: "alcuni modelli non risultano disponibili"

    "OpenRouter è configurato e raggiungibile; #{suffix}."
  end

  def present(%{
        url: url,
        title: title,
        baseline_ok?: baseline_ok?,
        issues: issues,
        warnings: warnings,
        assessment: assessment
      }) do
    status = if baseline_ok?, do: "superati", else: "problemi rilevati"

    details =
      [
        formatted_findings("Problemi", issues),
        formatted_findings("Avvisi", warnings)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    [
      "Controllo pagina: #{title || "senza titolo"}",
      url,
      "Controlli tecnici: #{status}",
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

  defp configured(:configured), do: "configurato"
  defp configured(_other), do: "non configurato"

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
