defmodule ExBlog.Agent.StateStore do
  @moduledoc """
  DETS-backed Spectre state store with optimistic concurrency.
  """

  @behaviour Spectre.State.Store

  alias ExBlog.Storage
  alias Spectre.State
  alias Spectre.State.Codec

  @impl true
  def load(_input, agent, opts) when is_atom(agent) and is_list(opts) do
    case conversation_id(opts) do
      nil ->
        {:ok, %State{}}

      conversation_id ->
        case Storage.fetch(storage_key(conversation_id, agent)) do
          :error -> {:ok, %State{conversation_id: conversation_id}}
          {:ok, entry} -> decode_entry(entry)
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
        persist(conversation_id, agent, state.revision, expected_revision, payload)
      end
    end
  end

  @spec delete(String.t(), module()) :: :ok | {:error, term()}
  def delete(conversation_id, agent) do
    conversation_id
    |> storage_key(agent)
    |> Storage.delete()
  end

  defp persist(conversation_id, agent, revision, expected_revision, payload) do
    key = storage_key(conversation_id, agent)

    Storage.update(key, nil, fn
      nil when expected_revision == 0 ->
        {:put, %{revision: revision, payload: payload}, :ok}

      %{revision: ^expected_revision} ->
        {:put, %{revision: revision, payload: payload}, :ok}

      current ->
        {:keep, {:error, {:stale_state, stored_revision(current)}}}
    end)
  end

  defp decode_entry(%{payload: payload, revision: revision}) do
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

  defp storage_key(conversation_id, agent),
    do: {:spectre_state, identity(conversation_id), agent_name(agent)}

  defp stored_revision(%{revision: revision}), do: revision
  defp stored_revision(_entry), do: nil
end
