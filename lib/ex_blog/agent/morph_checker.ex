defmodule ExBlog.Agent.MorphChecker do
  @moduledoc """
  Model-free Morph checker for ExBlog's explicitly rehearsable router mode.

  Spectre's bundled declarative checker refuses custom router modules before
  invoking them. ExBlog keeps that conservative default and supplies this
  host checker instead: it accepts only `ExBlog.Agent.RouterPipeline`, requires
  that pipeline's explicit rehearsal contract, and then uses Spectre's normal
  exact Definition loader, runtime Skill dispatch, evaluator, delta, and
  signed replay/regression receipt issuer against the real `ExBlog.Agent`.
  """

  alias ExBlog.Agent.RouterPipeline
  alias Spectre.Eval.Case, as: EvalCase
  alias Spectre.Governance.CandidateState
  alias Spectre.Governance.Checker.Declarative.Evaluator
  alias Spectre.Governance.Checker.Declarative.ReceiptIssuer
  alias Spectre.Governance.Checker.Declarative.Rehearsability
  alias Spectre.Governance.EvaluationDelta
  alias Spectre.Skill.Runtime.Loader

  @doc "Returns the checker versions required by the standard Morph review gate."
  @spec checker_versions() :: map()
  def checker_versions, do: ReceiptIssuer.checker_versions()

  @doc "Evaluates protected and Candidate-owned cases against exact Definition Refs."
  @spec run(Spectre.Definition.Store.config(), map(), [map()], keyword()) ::
          {:ok, EvaluationDelta.t(), [Spectre.Gate.Receipt.t()]} | {:error, term()}
  def run(store, candidate, cases, opts \\ [])

  def run(store, %{governance: %CandidateState{} = governance}, cases, opts)
      when is_list(cases) and is_list(opts) do
    if Keyword.keyword?(opts) do
      RouterPipeline.rehearse(fn -> run_checked(store, governance, cases, opts) end)
    else
      {:error, :invalid_ex_blog_morph_check_options}
    end
  end

  def run(_store, _candidate, _cases, _opts), do: {:error, :invalid_ex_blog_morph_check}

  defp run_checked(store, governance, cases, opts) do
    issued_at = Keyword.get(opts, :issued_at, System.system_time(:millisecond))
    candidate_ids = governance.candidate_case_ids || []
    candidate_cases = governance.candidate_cases || []

    with {:ok, snapshot} <- Rehearsability.agent_snapshot(agent: ExBlog.Agent),
         :ok <- verify_router_contract(snapshot),
         {:ok, protected} <- Evaluator.normalize_cases(cases),
         {:ok, owned} <- Evaluator.normalize_cases(candidate_cases),
         :ok <- Evaluator.verify_candidate_case_ids(owned, candidate_ids),
         all_cases = protected ++ owned,
         :ok <- Rehearsability.verify_cases(all_cases),
         {:ok, parent} <-
           Loader.load(
             store,
             governance.parent_definition_ref,
             ExBlog.Agent,
             runtime_only?: true
           ),
         {:ok, proposed} <-
           Loader.load(
             store,
             governance.candidate_definition_ref,
             ExBlog.Agent,
             runtime_only?: true
           ),
         :ok <- Rehearsability.verify_runtime(parent.runtime),
         :ok <- Rehearsability.verify_runtime(proposed.runtime),
         {:ok, parent_results} <- Evaluator.evaluate(parent, protected, snapshot),
         {:ok, candidate_results} <- Evaluator.evaluate(proposed, all_cases, snapshot),
         {:ok, delta} <-
           EvaluationDelta.new(parent_results, candidate_results,
             protected_cases: Enum.map(protected, &EvalCase.to_data/1),
             candidate_case_ids: candidate_ids
           ),
         {:ok, receipts} <- ReceiptIssuer.issue(governance, delta, issued_at) do
      {:ok, delta, receipts}
    end
  end

  defp verify_router_contract(snapshot) do
    with RouterPipeline <- Keyword.get(snapshot.router, :pipeline),
         true <- RouterPipeline.rehearsable?() do
      router =
        snapshot.router
        |> Keyword.put(:pipeline, nil)
        |> Keyword.put(:via, [:regex])
        |> Keyword.put(:semantic_cache?, false)
        |> Keyword.put(:llm_classifier?, false)

      Rehearsability.verify_live_path(%{snapshot | router: router})
    else
      _unsupported -> {:error, :ex_blog_router_pipeline_not_rehearsable}
    end
  end
end
