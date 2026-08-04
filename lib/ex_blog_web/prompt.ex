defmodule ExBlogWeb.Prompt do
  @moduledoc """
  Text prompts rendered from HEEx templates.

  Dynamic values cross this boundary only after credential redaction, byte
  limiting, and HTML escaping so untrusted article content cannot close the
  prompt's data markers.
  """

  use ExBlogWeb, :html

  alias ExBlog.Config
  alias Phoenix.HTML.Safe

  embed_templates "prompts/renderers/*"

  @spec classifier(map()) :: String.t()
  def classifier(assigns) when is_map(assigns) do
    assigns
    |> Map.put_new(:label_tree, "UNKNOWN")
    |> Map.put_new(:text, "")
    |> Map.put_new(:active_flow, "none")
    |> Map.put_new(:recent_chat, "none")
    |> classifier_prompt()
    |> rendered_to_string()
  end

  @spec article_generation(map()) :: String.t()
  def article_generation(assigns) when is_map(assigns) do
    assigns
    |> Map.put_new(:request, "")
    |> Map.put_new(:category, "")
    |> Map.put_new(:research_summary, "")
    |> Map.put_new(:source_urls, "")
    |> article_generation_prompt()
    |> rendered_to_string()
  end

  @spec article_revision(map()) :: String.t()
  def article_revision(assigns) when is_map(assigns) do
    assigns
    |> Map.put_new(:instructions, "")
    |> article_revision_prompt()
    |> rendered_to_string()
  end

  @spec article_translation(map()) :: String.t()
  def article_translation(assigns) when is_map(assigns) do
    assigns
    |> article_translation_prompt()
    |> rendered_to_string()
  end

  @spec article_seo(map()) :: String.t()
  def article_seo(assigns) when is_map(assigns) do
    assigns
    |> Map.put_new(:title, "")
    |> Map.put_new(:category, "")
    |> Map.put_new(:cover_alt, "")
    |> article_seo_prompt()
    |> rendered_to_string()
  end

  @doc "Renders the bounded prompt used for an AI-assisted title step."
  @spec editorial_title(map()) :: String.t()
  def editorial_title(assigns) when is_map(assigns) do
    assigns
    |> Map.put_new(:lang, "")
    |> Map.put_new(:category, "")
    |> Map.put_new(:brief, "")
    |> editorial_title_prompt()
    |> rendered_to_string()
  end

  @doc "Renders the bounded prompt used for an AI-assisted category step."
  @spec editorial_category(map()) :: String.t()
  def editorial_category(assigns) when is_map(assigns) do
    assigns
    |> Map.put_new(:lang, "")
    |> Map.put_new(:brief, "")
    |> Map.put_new(:category_options, "")
    |> editorial_category_prompt()
    |> rendered_to_string()
  end

  @doc "Renders the source-grounded summarization prompt for editorial research."
  @spec editorial_research(map()) :: String.t()
  def editorial_research(assigns) when is_map(assigns) do
    assigns
    |> Map.put_new(:topic, "")
    |> Map.put_new(:source_context, "")
    |> editorial_research_prompt()
    |> rendered_to_string()
  end

  @doc """
  Produces an escaped, redacted text fragment for an untrusted prompt value.

  This binary form is also safe for Spectre's runtime `.text.heex` renderer,
  which intentionally evaluates a small EEx-compatible prompt format rather
  than Phoenix HTML components.
  """
  @spec escape_text(term(), pos_integer()) :: String.t()
  def escape_text(value, limit \\ 8_000)

  def escape_text(nil, _limit), do: ""

  def escape_text(value, limit) when is_integer(limit) and limit > 0 do
    value
    |> to_string()
    |> Config.redact()
    |> String.slice(0, limit)
    |> escape_html()
  end

  @spec safe_text(term(), pos_integer()) :: Phoenix.HTML.safe()
  def safe_text(value, limit \\ 8_000), do: raw(escape_text(value, limit))

  defp escape_html(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp rendered_to_string(rendered) do
    rendered
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> String.replace(~r/<!--.*?-->/s, "")
    |> String.trim()
  end
end
