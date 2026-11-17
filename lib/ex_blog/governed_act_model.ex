defmodule ExBlog.GovernedActModel do
  @moduledoc """
  Compile-time, bilingual representation of the Governed Act Model manifesto.

  The Markdown files at the repository root are the source of truth. Embedding
  them at compile time keeps releases self-contained while `@external_resource`
  ensures that changing either document recompiles this module in development.
  """

  @italian_source Path.expand("../../GOVERNED_ACT_MODEL.md", __DIR__)
  @english_source Path.expand("../../GOVERNED_ACT_MODEL.en.md", __DIR__)

  @external_resource @italian_source
  @external_resource @english_source

  @languages ["it", "en"]

  @copy %{
    "it" => %{
      eyebrow: "Manifesto per sistemi agentici",
      summary:
        "La forma minima per separare ciò che l’intelligenza propone dal potere che produce conseguenze.",
      status: "costituzione operativa",
      source_label: "sorgente",
      language_label: "lingua",
      reading_label: "lettura",
      words_label: "parole",
      minutes_label: "min",
      primitives_label: "Le quattro forme",
      primitives_summary:
        "Quattro significati, indipendenti dall’implementazione, rendono decidibile il confine tra convinzione e conseguenza.",
      toc_label: "Indice del manifesto",
      introduction_label: "Fondamento e quattro forme",
      document_label: "Testo integrale",
      home_eyebrow: "La costituzione di Spectre",
      home_title: "L’intelligenza propone. Non si concede il potere.",
      home_summary:
        "Il Governed Act Model racchiude la logica e la filosofia che ogni sistema agentico dovrebbe seguire: separare conoscenza, capacità e autorità, registrare ogni conseguenza governata e non cancellare ciò che resta irrisolto.",
      home_cta: "Leggi il manifesto integrale",
      home_note: "Un modello, quattro forme, nessuna porta laterale.",
      flow: ["proposta", "Mandate + Evidence", "Act", "mondo", "Duty se irrisolto"],
      terms: [
        %{
          name: "Mandate",
          verb: "delimita",
          description: "Da dove viene il diritto di proporre una conseguenza."
        },
        %{
          name: "Evidence",
          verb: "informa",
          description: "Che cosa abbiamo ragione di credere, senza trasformarlo in autorità."
        },
        %{
          name: "Act",
          verb: "registra",
          description: "L’esercizio riconosciuto di autorità, prima che il potere sia rilasciato."
        },
        %{
          name: "Duty",
          verb: "conserva",
          description: "Ciò che il sistema non ha ancora il diritto di chiamare risolto."
        }
      ]
    },
    "en" => %{
      eyebrow: "A manifesto for agentic systems",
      summary:
        "The minimum form that separates what intelligence proposes from the power that produces consequences.",
      status: "operational constitution",
      source_label: "source",
      language_label: "language",
      reading_label: "reading",
      words_label: "words",
      minutes_label: "min",
      primitives_label: "The four forms",
      primitives_summary:
        "Four implementation-independent meanings make the boundary between conviction and consequence decidable.",
      toc_label: "Manifesto index",
      introduction_label: "Foundation and four forms",
      document_label: "Full text",
      home_eyebrow: "The constitution of Spectre",
      home_title: "Intelligence proposes. It does not grant itself power.",
      home_summary:
        "The Governed Act Model contains the logic and philosophy every agentic system should follow: separate knowledge, capability, and authority; record every governed consequence; and never erase what remains unresolved.",
      home_cta: "Read the full manifesto",
      home_note: "One model, four forms, no side doors.",
      flow: ["proposal", "Mandate + Evidence", "Act", "world", "Duty if unresolved"],
      terms: [
        %{
          name: "Mandate",
          verb: "bounds",
          description: "Where the right to propose a consequence comes from."
        },
        %{
          name: "Evidence",
          verb: "informs",
          description: "What we have reason to believe, without turning it into authority."
        },
        %{
          name: "Act",
          verb: "records",
          description: "The recognised exercise of authority before capability is released."
        },
        %{
          name: "Duty",
          verb: "preserves",
          description: "What the system does not yet have the right to call resolved."
        }
      ]
    }
  }

  @sanitize_options Keyword.put(
                      MDEx.Document.default_sanitize_options(),
                      :add_generic_attributes,
                      ["id"]
                    )

  @documents Enum.into(
               %{"it" => @italian_source, "en" => @english_source},
               %{},
               fn {language, path} ->
                 source = File.read!(path)

                 [heading, thesis, body] =
                   String.split(source, ~r/\r?\n\r?\n/u, parts: 3)

                 title = heading |> String.trim() |> String.trim_leading("#") |> String.trim()

                 sections =
                   body
                   |> then(&Regex.scan(~r/^##\s+(.+?)\s*$/mu, &1, capture: :all_but_first))
                   |> Enum.map(fn [section_title] ->
                     %{title: section_title, id: MDEx.anchorize(section_title)}
                   end)

                 {:ok, html} =
                   MDEx.to_html(body,
                     extension: [
                       autolink: true,
                       header_id_prefix: "",
                       strikethrough: true
                     ],
                     parse: [smart: true],
                     sanitize: @sanitize_options
                   )

                 words = source |> String.split(~r/\s+/u, trim: true) |> length()

                 document =
                   @copy
                   |> Map.fetch!(language)
                   |> Map.merge(%{
                     language: language,
                     file: Path.basename(path),
                     title: title,
                     thesis: String.trim(thesis),
                     markdown: source,
                     html: html,
                     sections: sections,
                     words: words,
                     reading_minutes: max(div(words + 199, 200), 1)
                   })

                 {language, document}
               end
             )

  @spec languages() :: [String.t()]
  def languages, do: @languages

  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(language), do: Map.fetch(@documents, language)

  @spec fetch!(String.t()) :: map()
  def fetch!(language), do: Map.fetch!(@documents, language)
end
