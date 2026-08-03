defmodule ExBlog.Agent.StateStore do
  @moduledoc """
  SQLite-backed Spectre state store with optimistic concurrency.
  """

  @behaviour Spectre.State.Store

  import Ecto.Query

  alias ExBlog.Agent.StateEntry
  alias ExBlog.Repo
  alias Spectre.State
  alias Spectre.State.Codec

  @impl true
  def load(_input, agent, opts) when is_atom(agent) and is_list(opts) do
    case conversation_id(opts) do
      nil ->
        {:ok, %State{}}

      conversation_id ->
        case Repo.get_by(StateEntry, conversation_id: conversation_id, agent: agent_name(agent)) do
          nil -> {:ok, %State{conversation_id: conversation_id}}
          %StateEntry{} = entry -> decode_entry(entry)
        end
    end
  end

  @impl true
  def compare_and_swap(%State{} = state, expected_revision, _input, agent, opts)
      when is_integer(expected_revision) and expected_revision >= 0 and is_atom(agent) and
             is_list(opts) do
    conversation_id = identity(state.conversation_id) || conversation_id(opts)

    if is_nil(conversation_id) do
      :ok
    else
      with :ok <- validate_revision(state.revision, expected_revision),
           {:ok, payload} <- Codec.encode(state) do
        persist(conversation_id, agent_name(agent), state.revision, expected_revision, payload)
      end
    end
  end

  @spec delete(String.t(), module()) :: :ok
  def delete(conversation_id, agent) do
    StateEntry
    |> where(
      [entry],
      entry.conversation_id == ^identity(conversation_id) and entry.agent == ^agent_name(agent)
    )
    |> Repo.delete_all()

    :ok
  end

  defp persist(conversation_id, agent, revision, 0, payload) do
    now = DateTime.utc_now()

    case Repo.insert_all(
           StateEntry,
           [
             %{
               conversation_id: conversation_id,
               agent: agent,
               revision: revision,
               payload: payload,
               inserted_at: now,
               updated_at: now
             }
           ],
           on_conflict: :nothing,
           conflict_target: [:conversation_id, :agent]
         ) do
      {1, _rows} -> :ok
      {0, _rows} -> stale_state(conversation_id, agent)
    end
  end

  defp persist(conversation_id, agent, revision, expected_revision, payload) do
    query =
      from entry in StateEntry,
        where:
          entry.conversation_id == ^conversation_id and entry.agent == ^agent and
            entry.revision == ^expected_revision

    case Repo.update_all(query,
           set: [revision: revision, payload: payload, updated_at: DateTime.utc_now()]
         ) do
      {1, _rows} -> :ok
      {0, _rows} -> stale_state(conversation_id, agent)
    end
  end

  defp stale_state(conversation_id, agent) do
    actual =
      StateEntry
      |> where([entry], entry.conversation_id == ^conversation_id and entry.agent == ^agent)
      |> select([entry], entry.revision)
      |> Repo.one()

    {:error, {:stale_state, actual}}
  end

  defp decode_entry(%StateEntry{payload: payload, revision: revision}) do
    with {:ok, %State{} = state} <- Codec.decode(payload),
         true <- state.revision == revision do
      {:ok, state}
    else
      false -> {:error, {:state_revision_mismatch, revision}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_revision(revision, expected) when revision == expected + 1, do: :ok

  defp validate_revision(revision, expected),
    do: {:error, {:invalid_state_revision_transition, expected, revision}}

  defp conversation_id(opts), do: opts |> Keyword.get(:conversation_id) |> identity()
  defp identity(nil), do: nil
  defp identity(value) when is_binary(value), do: value
  defp identity(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp identity(_value), do: nil
  defp agent_name(agent), do: inspect(agent)
end
