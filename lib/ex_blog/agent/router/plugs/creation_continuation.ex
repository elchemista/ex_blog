defmodule ExBlog.Agent.Router.Plugs.CreationContinuation do
  @moduledoc """
  Deterministic routing evidence for an active editorial workflow step.

  Capture rules advertise the private provider name `:creation_continuation`,
  so no ordinary Spectre provider can see them outside intake. In Spectre
  0.4 that name is a compiled `Spectre.Router.Adapter` id: the Agent declares
  this module in its router `via:`, which is what makes the capture leaves'
  `via: [:creation_continuation]` resolvable at compile time.

  The module therefore owns two halves of one provider:

    * `evaluate/1` is the Adapter contract. Given the persisted cursor it
      returns hard evidence for exactly the leaf that owns the current step,
      and nothing else. It sees no handlers, candidates, or raw host context.
    * `call/2` is the pipeline plug that decides whether that evidence may be
      collected at all. Global interrupts and explicit slash commands keep
      precedence over the cursor, and out-of-flow regex candidates are dropped
      before the Adapter speaks. Evidence-only Adapters cannot express that
      precedence policy, which is why the plug remains the pipeline entry point.
  """

  use Spectre.Router.Adapter,
    id: :creation_continuation,
    accept: 1.0,
    margin: 1.0,
    strength: :hard

  @behaviour Spectre.Router.Plug

  alias ExBlog.Agent.Skills.Editorial
  alias Spectre.Router.Adapter
  alias Spectre.Router.Adapter.Request
  alias Spectre.Router.Adapter.RuleView
  alias Spectre.Router.Candidate
  alias Spectre.Router.Context
  alias Spectre.Rule
  alias Spectre.State

  @impl Spectre.Router.Adapter
  def evaluate(%Request{current_flow: nil}), do: {:skip, :no_active_cursor}

  def evaluate(%Request{current_flow: flow, current_scope: scope, rules: rules}) do
    case Enum.find(rules, &current_step_leaf?(&1, flow, scope)) do
      %RuleView{} = leaf -> {:ok, result(leaf, 1.0, margin: 1.0)}
      nil -> {:skip, :cursor_without_capture_leaf}
    end
  end

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

  @spec route_continuation(Context.t()) :: {:cont, Context.t()} | {:error, term()}
  defp route_continuation(
         %Context{
           host_context: %{state: %State{} = state},
           input: input,
           rules: rules
         } = context
       ) do
    with true <- Editorial.active?(state),
         %Rule{} = rule <- current_step_rule(rules, state) do
      if Rule.match?(rule, input.text) do
        # A regex declared on the active leaf is evaluated here rather than by
        # the global regex plug. This keeps URL and review controls scoped to
        # the persisted cursor while preserving `:regex` as the observable
        # strategy, which the Adapter contract cannot report on its behalf.
        {:cont, add_regex_evidence(context, rule, input.text, state)}
      else
        # The cursor is stronger evidence than linguistic similarity: during the
        # language step, for example, "English" is data rather than a new intent.
        # Scoring that leaf is the Adapter's job.
        run_adapter(context, state)
      end
    else
      _inactive_or_missing_rule -> {:cont, context}
    end
  end

  defp route_continuation(%Context{} = context), do: {:cont, context}

  @spec add_regex_evidence(Context.t(), Rule.t(), String.t(), State.t()) :: Context.t()
  defp add_regex_evidence(%Context{} = context, %Rule{} = rule, text, %State{} = state) do
    candidate =
      Candidate.from_rule(rule, :regex, text,
        score: 1.0,
        margin: 1.0,
        strength: :hard,
        accepted?: true
      )

    context
    |> Context.add_candidate(candidate)
    |> Context.put_trace({:regex, state.current_flow})
  end

  @spec run_adapter(Context.t(), State.t()) :: {:cont, Context.t()} | {:error, term()}
  defp run_adapter(%Context{} = context, %State{} = state) do
    case Adapter.run(context, :creation_continuation) do
      {:cont, %Context{} = context} ->
        {:cont, Context.put_trace(context, {:creation_continuation, state.current_flow})}

      {:error, _reason} = error ->
        # Only a missing or drifted compiled Adapter reaches this clause; a
        # failing `evaluate/1` is contained by Spectre and skips the provider.
        error
    end
  end

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

  @spec current_step_leaf?(RuleView.t(), atom(), Spectre.Definition.scope() | nil) :: boolean()
  defp current_step_leaf?(%RuleView{flow: flow, scope: scope, global?: false}, flow, scope),
    do: true

  defp current_step_leaf?(%RuleView{}, _flow, _scope), do: false
end
