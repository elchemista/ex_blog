defmodule ExBlog.Agent.StateStoreTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Agent.StateStore
  alias Spectre.Input
  alias Spectre.State

  test "persists state with optimistic concurrency" do
    input = Input.new("hello")
    opts = [conversation_id: "conversation-1"]

    assert {:ok, %State{revision: 0}} = StateStore.load(input, ExBlog.Agent, opts)

    state = %State{conversation_id: "conversation-1", revision: 1, data: %{safe: true}}
    assert :ok = StateStore.compare_and_swap(state, 0, input, ExBlog.Agent, opts)
    assert {:ok, ^state} = StateStore.load(input, ExBlog.Agent, opts)

    stale = %{state | revision: 1, data: %{safe: false}}

    assert {:error, {:stale_state, 1}} =
             StateStore.compare_and_swap(stale, 0, input, ExBlog.Agent, opts)
  end
end
