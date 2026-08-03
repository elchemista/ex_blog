defmodule ExBlog.Agent.Router.Plugs.CreationContinuation do
  @moduledoc """
  Adds deterministic routing evidence for the active article creation step.

  Explicit regex commands and global interrupts retain precedence. Otherwise,
  the current nested flow owns the free-form reply without another model call.
  """

  @behaviour Spectre.Router.Plug

  alias ExBlog.Agent.Skills.Editorial
  alias Spectre.Router.Candidate
  alias Spectre.Router.Context
  alias Spectre.Rule
  alias Spectre.State

  @impl Spectre.Router.Plug
  def init(opts), do: opts

  @impl Spectre.Router.Plug
  def call(%Context{} = context, _state) do
    if Context.halted?(context) or Context.hard_candidate?(context) do
      {:cont, context}
    else
      route_continuation(context)
    end
  end

  @spec route_continuation(Context.t()) :: {:cont, Context.t()}
  defp route_continuation(
         %Context{
           host_context: %{state: %State{} = state},
           input: input,
           rules: rules
         } = context
       ) do
    with true <- Editorial.active?(state),
         %Rule{} = rule <- current_step_rule(rules, state) do
      candidate =
        Candidate.from_rule(rule, :creation_continuation, input.text,
          score: 1.0,
          margin: 1.0,
          strength: :hard,
          accepted?: true
        )

      {:cont,
       context
       |> Context.add_candidate(candidate)
       |> Context.put_trace({:creation_continuation, state.current_flow})}
    else
      _inactive_or_missing_rule -> {:cont, context}
    end
  end

  defp route_continuation(%Context{} = context), do: {:cont, context}

  @spec current_step_rule([Rule.t()], State.t()) :: Rule.t() | nil
  defp current_step_rule(rules, %State{current_flow: flow, current_scope: scope}) do
    Enum.find(rules, fn rule ->
      rule.flow == flow and rule.scope == scope and not rule.global?
    end)
  end
end
