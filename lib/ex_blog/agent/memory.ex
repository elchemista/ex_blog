defmodule ExBlog.Agent.Memory do
  @moduledoc """
  Minimal durable memory adapter for Spectre.

  It stores redaction-safe routing examples. Infrastructure configuration and
  provider credentials are never part of the persisted payload.
  """

  import Ecto.Query

  alias ExBlog.Agent.MemoryEntry
  alias ExBlog.Config
  alias ExBlog.Repo

  @spec recall(String.t(), keyword()) :: {:ok, [map()]}
  def recall(text, opts) when is_binary(text) and is_list(opts) do
    agent = opts |> Keyword.get(:agent) |> agent_name()

    memories =
      MemoryEntry
      |> where([entry], entry.agent == ^agent and entry.cue == ^text)
      |> order_by([entry], desc: entry.updated_at)
      |> limit(5)
      |> Repo.all()
      |> Enum.map(&%{cue: &1.cue, label: &1.label, verified?: &1.verified})

    {:ok, memories}
  end

  @spec remember(Spectre.Input.t(), Spectre.Result.t(), module(), keyword()) ::
          :ok | {:error, term()}
  def remember(input, result, agent, _opts) do
    label = route_label(result)

    if safe_cue?(input.text) and is_binary(label) and label != "UNSAFE" do
      result =
        %MemoryEntry{}
        |> MemoryEntry.changeset(%{
          agent: agent_name(agent),
          cue: String.slice(input.text, 0, 2_000),
          label: label,
          verified: false
        })
        |> Repo.insert()

      case result do
        {:ok, _entry} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp route_label(%{route: %{label: label}}) when is_atom(label), do: Atom.to_string(label)
  defp route_label(%{route: %{label: label}}) when is_binary(label), do: label
  defp route_label(_result), do: nil

  defp safe_cue?(text) when is_binary(text) and text != "" do
    redacted = Config.redact(text)
    redacted == text and not String.contains?(text, "[REDACTED]")
  end

  defp safe_cue?(_text), do: false

  defp agent_name(nil), do: "unknown"
  defp agent_name(agent) when is_atom(agent), do: inspect(agent)
  defp agent_name(agent) when is_binary(agent), do: agent
  defp agent_name(_agent), do: "unknown"
end
