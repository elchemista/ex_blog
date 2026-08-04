defmodule ExBlog.Agent.Actions.Provider do
  @moduledoc """
  Bridges the Kinetic action catalog to the context-aware editorial executor.

  Kinetic selects and validates an operation. Spectre retains ownership of
  policy, staging, persistence, idempotency, and execution through this
  provider.

  `actions/1` compiles the `@al` annotations from `KineticActions` into Spectre
  action schemas. `execute/3` then dispatches only to an already-existing atom
  and only when `Actions` exports the required context-aware arity. This keeps
  model-produced action names from creating atoms or reaching arbitrary
  functions.
  """

  @behaviour Spectre.Action.Provider

  alias ExBlog.Agent.Actions
  alias ExBlog.Agent.KineticActions
  alias Spectre.Action
  alias Spectre.Context

  @impl Spectre.Action.Provider
  def actions(opts) do
    opts
    |> Keyword.put(:module, KineticActions)
    |> Spectre.Kinetic.Actions.actions()
  end

  @impl Spectre.Action.Provider
  def execute(%Action{name: name, args: args}, %Context{} = ctx, _opts) do
    with {:ok, function} <- existing_function(name),
         :ok <- ensure_context_action(function) do
      apply(Actions, function, [args, ctx])
    end
  end

  defp existing_function(name) when is_atom(name) and not is_nil(name), do: {:ok, name}

  defp existing_function(name) when is_binary(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> {:error, {:unknown_action_name, name}}
  end

  defp existing_function(name), do: {:error, {:invalid_action_name, name}}

  defp ensure_context_action(function) do
    if Code.ensure_loaded?(Actions) and function_exported?(Actions, function, 2),
      do: :ok,
      else: {:error, {:undefined_context_action, Actions, function, 2}}
  end
end
