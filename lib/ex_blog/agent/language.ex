defmodule ExBlog.Agent.Language do
  @moduledoc """
  Deterministic language parsing for editorial flows and article commands.

  Language selection is a bounded vocabulary problem, so it does not need an
  LLM classifier. Codes and common language names are matched with regular
  expressions, then resolved only against the deployment's configured list.
  This keeps the workflow predictable while article generation and translation
  remain free to use any configured target language.
  """

  @aliases %{
    "ar" => ~w(arabic),
    "de" => ~w(german),
    "en" => ~w(english),
    "es" => ~w(spanish),
    "fr" => ~w(french),
    "it" => ~w(italian),
    "ja" => ~w(japanese),
    "ko" => ~w(korean),
    "nl" => ~w(dutch),
    "pl" => ~w(polish),
    "pt" => ~w(portuguese),
    "ru" => ~w(russian),
    "tr" => ~w(turkish),
    "uk" => ~w(ukrainian),
    "zh" => ~w(chinese)
  }

  @type parse_result :: {:ok, String.t()} | :error

  @doc "Parses one configured language from a short natural-language reply."
  @spec parse(String.t(), [String.t()]) :: parse_result()
  def parse(text, supported) when is_binary(text) and is_list(supported) do
    languages = normalized_languages(supported)
    value = normalize(text)

    with :error <- exact_code(value, languages),
         :error <- named_language(value, languages) do
      explicit_code(value, languages)
    end
  end

  def parse(_text, _supported), do: :error

  @doc "Parses a target language introduced by `to`, `into`, or `in`."
  @spec parse_target(String.t(), [String.t()]) :: parse_result()
  def parse_target(text, supported) when is_binary(text) and is_list(supported) do
    case Regex.run(
           ~r/(?:^|\s)(?:to|into|in)\s+(.{1,80}?)\s*[.!?]?\s*$/iu,
           text,
           capture: :all_but_first
         ) do
      [target] -> parse(target, supported)
      _no_target -> parse(text, supported)
    end
  end

  def parse_target(_text, _supported), do: :error

  @doc "Finds a configured language code used as a standalone command token."
  @spec code_in(String.t(), [String.t()]) :: String.t() | nil
  def code_in(text, supported) when is_binary(text) and is_list(supported) do
    Enum.find(supported, fn language ->
      Regex.match?(
        ~r/(?:^|[\s\/:])#{Regex.escape(String.downcase(language))}(?:[\s\/:]|$)/iu,
        String.downcase(text)
      )
    end)
  end

  def code_in(_text, _supported), do: nil

  defp exact_code(value, languages) do
    case Map.fetch(languages, value) do
      {:ok, language} -> {:ok, language}
      :error -> :error
    end
  end

  defp named_language(value, languages) do
    matches =
      @aliases
      |> Enum.flat_map(&alias_matches(&1, value, languages))
      |> Enum.uniq()

    case matches do
      [language] -> {:ok, language}
      _ambiguous_or_missing -> :error
    end
  end

  defp alias_matches({base, aliases}, value, languages) do
    case resolve_base(base, languages) do
      nil -> []
      language -> if Enum.any?(aliases, &word_present?(value, &1)), do: [language], else: []
    end
  end

  defp explicit_code(value, languages) do
    codes = languages |> Map.keys() |> Enum.map_join("|", &Regex.escape/1)

    if codes == "" do
      :error
    else
      regex =
        Regex.compile!(
          "^(?:(?:language|lang|locale|use|in|to|write(?: it)? in)\\s*[:=]?\\s*)?(#{codes})(?:\\s+please)?$",
          "iu"
        )

      case Regex.run(regex, value, capture: :all_but_first) do
        [code] -> Map.fetch(languages, String.downcase(code))
        _missing -> :error
      end
    end
  end

  defp resolve_base(base, languages) do
    case Map.get(languages, base) do
      nil ->
        languages
        |> Enum.filter(fn {code, _language} -> String.starts_with?(code, base <> "-") end)
        |> Enum.map(&elem(&1, 1))
        |> case do
          [language] -> language
          _ambiguous_or_missing -> nil
        end

      language ->
        language
    end
  end

  defp normalized_languages(supported) do
    Map.new(supported, fn language -> {String.downcase(language), language} end)
  end

  defp normalize(text) do
    text
    |> String.trim()
    |> String.downcase()
    |> String.trim(" \t\r\n.!?")
  end

  defp word_present?(text, word) do
    Regex.match?(~r/(?:^|[^\p{L}])#{Regex.escape(word)}(?:[^\p{L}]|$)/iu, text)
  end
end
