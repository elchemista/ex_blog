defmodule ExBlog.Agent.Memory do
  @moduledoc """
  Minimal DETS-backed memory adapter for Spectre.

  Memory and semantic routing have different jobs. The semantic cache stores
  vectors that can select a route; this adapter recalls only entries under the
  same bounded text cue so a runtime may present recent, verified-safe routing
  context without performing another similarity search.

  Only the cue, selected label, and review flag are persisted. The reply,
  action arguments, article content, infrastructure configuration, and provider
  credentials are never part of the payload. A cue is rejected when redaction
  would change it, and unsafe routes are never remembered.
  """

  alias ExBlog.Config
  alias ExBlog.Storage

  @doc "Returns up to five memories stored under the exact bounded cue."
  @spec recall(String.t(), keyword()) :: {:ok, [map()]}
  def recall(text, opts) when is_binary(text) and is_list(opts) do
    agent = opts |> Keyword.get(:agent) |> agent_name()
    cue = String.slice(text, 0, 2_000)

    memories =
      case Storage.fetch(storage_key(agent, cue)) do
        {:ok, entries} when is_list(entries) -> entries
        _missing -> []
      end

    {:ok, memories}
  end

  @doc "Stores a redaction-safe cue and route label after a completed turn."
  @spec remember(Spectre.Input.t(), Spectre.Result.t(), module(), keyword()) ::
          :ok | {:error, term()}
  def remember(input, result, agent, _opts) do
    label = route_label(result)

    if safe_cue?(input.text) and is_binary(label) and label != "UNSAFE" do
      cue = String.slice(input.text, 0, 2_000)
      entry = %{cue: cue, label: label, verified?: false}

      Storage.update(storage_key(agent_name(agent), cue), [], &prepend_entry(&1, entry))
    else
      :ok
    end
  end

  defp route_label(%{route: %{label: label}}) when is_atom(label), do: Atom.to_string(label)
  defp route_label(%{route: %{label: label}}) when is_binary(label), do: label
  defp route_label(_result), do: nil

  defp safe_cue?(text) when is_binary(text) and text != "" do
    # Comparing the redacted value with the original is stricter than merely
    # checking for known token prefixes and follows the central Config policy.
    redacted = Config.redact(text)
    redacted == text and not String.contains?(text, "[REDACTED]")
  end

  defp safe_cue?(_text), do: false

  defp prepend_entry(entries, entry) do
    entries = if is_list(entries), do: entries, else: []
    {:put, Enum.take([entry | entries], 5), :ok}
  end

  defp agent_name(nil), do: "unknown"
  defp agent_name(agent) when is_atom(agent), do: inspect(agent)
  defp agent_name(agent) when is_binary(agent), do: agent
  defp agent_name(_agent), do: "unknown"
  defp storage_key(agent, cue), do: {:spectre_memory, agent_name(agent), cue}
end
