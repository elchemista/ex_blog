defmodule ExBlog.Agent.Router.Plugs.CreationContinuation do
  @moduledoc """
  Adds deterministic routing evidence for an active editorial workflow step.

  Global interrupts and explicit slash commands retain precedence. Otherwise,
  the current nested flow owns the free-form reply without another model call.

  Capture rules advertise the private provider name `:creation_continuation`
  for compatibility with the original article-creation flow.
  Normal Spectre providers therefore cannot see them outside intake. This plug
  is the sole bridge: it reads the persisted cursor, finds the matching scoped
  rule, and emits hard evidence for exactly that leaf.
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
    cond do
      Context.halted?(context) ->
        {:cont, context}

      not active_editorial_workflow?(context) ->
        {:cont, context}

      global_interrupt?(context) ->
        # Safety, cancellation, and image attachment are global rules. They
        # must remain available while any intake leaf owns the conversation.
        {:cont, context}

      explicit_slash_command?(context) ->
        # A leading slash is the administrator's escape hatch for deliberately
        # invoking another command without first cancelling the intake flow.
        {:cont, context}

      true ->
        # A future skill may add a non-command regex that also matches an
        # workflow answer. The persisted cursor is stronger than that out-of-flow
        # evidence, so discard only non-global regex candidates before adding
        # the continuation candidate.
        context
        |> drop_non_global_regex_candidates()
        |> route_continuation()
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
      # A regex declared on the active leaf is evaluated here rather than by
      # the global regex plug. This keeps URL and review controls scoped to the
      # persisted cursor while preserving `:regex` as the observable strategy.
      provider = if Rule.match?(rule, input.text), do: :regex, else: :creation_continuation

      # The cursor is stronger evidence than linguistic similarity: during the
      # language step, for example, "English" is data rather than a new intent.
      candidate =
        Candidate.from_rule(rule, provider, input.text,
          score: 1.0,
          margin: 1.0,
          strength: :hard,
          accepted?: true
        )

      {:cont,
       context
       |> Context.add_candidate(candidate)
       |> Context.put_trace({provider, state.current_flow})}
    else
      _inactive_or_missing_rule -> {:cont, context}
    end
  end

  defp route_continuation(%Context{} = context), do: {:cont, context}

  @spec active_editorial_workflow?(Context.t()) :: boolean()
  defp active_editorial_workflow?(%Context{host_context: %{state: %State{} = state}}),
    do: Editorial.active?(state)

  defp active_editorial_workflow?(_context), do: false

  @spec global_interrupt?(Context.t()) :: boolean()
  defp global_interrupt?(%Context{candidates: candidates}) do
    Enum.any?(candidates, fn
      %Candidate{accepted?: true, handler: handler, rule: %Rule{global?: true}}
      when not is_nil(handler) ->
        true

      _candidate ->
        false
    end)
  end

  @spec explicit_slash_command?(Context.t()) :: boolean()
  defp explicit_slash_command?(%Context{input: %{text: text}, candidates: candidates}) do
    String.starts_with?(String.trim_leading(text), "/") and
      Enum.any?(candidates, fn
        %Candidate{provider: :regex, accepted?: true, handler: handler}
        when not is_nil(handler) ->
          true

        _candidate ->
          false
      end)
  end

  @spec drop_non_global_regex_candidates(Context.t()) :: Context.t()
  defp drop_non_global_regex_candidates(%Context{} = context) do
    {discarded, retained} =
      Enum.split_with(context.candidates, fn
        %Candidate{provider: :regex, rule: %Rule{global?: false}} -> true
        _candidate -> false
      end)

    labels = Enum.map(discarded, & &1.label)

    context
    |> Map.put(:candidates, retained)
    |> Context.put_trace({:creation_continuation_discarded_regex, labels})
  end

  @spec current_step_rule([Rule.t()], State.t()) :: Rule.t() | nil
  defp current_step_rule(rules, %State{current_flow: flow, current_scope: scope}) do
    Enum.find(rules, fn rule ->
      rule.flow == flow and rule.scope == scope and not rule.global?
    end)
  end
end
