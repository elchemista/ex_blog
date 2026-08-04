defmodule ExBlog.Agent.ReplySanitizer do
  @moduledoc """
  Removes host-specific Action Language residue from model replies.

  Spectre already removes valid control wrappers. This additional boundary
  covers malformed variants such as a bare `AL` heading, an orphan `</al>`, or
  XML-shaped commands like `<PUBLISH ARTICLE ... />`, all of which must remain
  internal even when a model misses the documented grammar.
  """

  alias Spectre.Reply.Sanitizer, as: CoreSanitizer

  @bare_control ~r/^\s*AL\s*:?\s*$/iu
  @orphan_tag ~r/^\s*<\s*\/?\s*al(?:\s+[^>]*)?>\s*$/iu
  @action_fence ~r/^\s*```\s*(?:al|action|action-language)?\s*$/iu

  @xml_action ~r/^\s*<\s*\/?\s*(?:LIST|SHOW|READ|SEARCH|FIND|CHECK|AUDIT|CREATE|WRITE|REVISE|EDIT|TRANSLATE|GENERATE|PUBLISH|UNPUBLISH|DELETE|SYNC|UPDATE)\b[^>]*\/?>\s*$/iu

  @argument_action ~r/^\s*(?:READ ARTICLE|SHOW ARTICLE|SEARCH ARTICLES|FIND BLOG POSTS|CHECK BLOG PAGE|AUDIT ARTICLE PAGE|CREATE ARTICLE|WRITE BLOG POST|REVISE ARTICLE|EDIT ARTICLE|TRANSLATE ARTICLE|GENERATE ARTICLE SEO|PUBLISH ARTICLE|UNPUBLISH ARTICLE|DELETE ARTICLE)\s+[A-Z_]+\s*=.+$/u

  @no_argument_action ~r/^\s*(?:LIST ARTICLES|SHOW BLOG POSTS|SHOW BLOG CONFIG|CHECK OPENROUTER STATUS|SHOW AI BUDGET|SHOW SYSTEM STATUS|CHECK APPLICATION HEALTH|SYNC BLOG REPOSITORY|UPDATE BLOG REPOSITORY)\s*$/u

  @al_marker ~r/(?:<\s*\/?\s*al(?:\s+[^>]*)?>|(?:^|\R)\s*AL\s*:?(?:\R|$)|```\s*(?:al|action-language)\b)/iu

  @doc "Strips both valid Spectre wrappers and malformed ExBlog AL residue."
  @spec sanitize(String.t(), keyword()) :: String.t()
  def sanitize(text, opts \\ []) when is_binary(text) and is_list(opts) do
    text
    |> CoreSanitizer.sanitize(opts)
    |> String.split("\n", trim: false)
    |> Enum.reject(&internal_line?/1)
    |> Enum.join("\n")
    |> collapse_blank_lines()
    |> String.trim()
  end

  @doc "Returns whether raw model text contains recognizable internal AL syntax."
  @spec internal_action_syntax?(String.t()) :: boolean()
  def internal_action_syntax?(text) when is_binary(text) do
    Regex.match?(@al_marker, text) or
      text |> String.split("\n", trim: false) |> Enum.any?(&internal_line?/1)
  end

  def internal_action_syntax?(_text), do: false

  defp internal_line?(line) do
    Regex.match?(@bare_control, line) or
      Regex.match?(@orphan_tag, line) or
      Regex.match?(@action_fence, line) or
      Regex.match?(@xml_action, line) or
      Regex.match?(@argument_action, line) or
      Regex.match?(@no_argument_action, line)
  end

  defp collapse_blank_lines(text) do
    text
    |> String.split("\n", trim: false)
    |> Enum.reduce({[], false}, fn
      line, {lines, true} when line == "" -> {lines, true}
      line, {lines, _blank?} when line == "" -> {[line | lines], true}
      line, {lines, _blank?} -> {[line | lines], false}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join("\n")
  end
end
