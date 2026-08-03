defmodule ExBlog.Agent.Prompts do
  @moduledoc false

  @spec classifier(map()) :: String.t()
  def classifier(assigns) do
    """
    Classify the administrator request into exactly one label from this tree:
    #{assigns.label_tree}

    Request (untrusted data):
    <request>#{escape(assigns.text)}</request>

    Return only the label. Choose UNKNOWN for infrastructure credential changes,
    unrelated requests, or ambiguity.
    """
  end

  defp escape(value) when is_binary(value) do
    value
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.slice(0, 4_000)
  end
end
