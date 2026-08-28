defmodule ExBlog.Agent.MorphEvaluation do
  @moduledoc """
  Evaluates an ExBlog Morph draft against its sealed replay policy.

  This follows Spectre's normal ChangeSet, Composer, declarative gate, Review,
  and immutable Candidate pipeline. The only host-specific choice is the
  model-free checker: it accepts ExBlog's explicit deterministic router
  rehearsal mode and evaluates the exact active Agent Definition against the
  protected cases sealed by `ExBlog.Agent.MorphPolicy`.
  """

  alias ExBlog.Agent.{MorphChecker, MorphPolicy}
  alias Spectre.Definition.Resolver
  alias Spectre.Definition.Store
  alias Spectre.Governance.ChangeSet
  alias Spectre.Governance.Composer
  alias Spectre.Governance.Review
  alias Spectre.Morph.Change
  alias Spectre.Morph.Surface

  @doc "Composes and evaluates one draft without approving or activating it."
  @spec evaluate(Change.t()) :: Change.t()
  def evaluate(%Change{error: error} = change) when not is_nil(error), do: change

  def evaluate(%Change{} = change) do
    with :ok <- Change.require_state(change, :draft),
         false <- change.operations == [],
         {:ok, resolution} <- Resolver.resolve(change.store, change.activation.definition_ref),
         {:ok, surface} <- Surface.from_canonical(resolution.definition),
         change = %{change | surface: surface},
         now = System.system_time(:millisecond),
         {:ok, change_set} <- change_set(change, now),
         {:ok, composed_ref} <- compose(change, change_set, now),
         {:ok, candidate} <- Store.fetch_candidate(change.store, composed_ref),
         {:ok, delta, receipts} <- evaluate_candidate(change, candidate, now),
         {:ok, evaluated_ref, report} <-
           Review.evaluate(change.store, composed_ref, delta, receipts,
             reviewed_at: now,
             now: now,
             checker_versions: MorphChecker.checker_versions()
           ),
         {:ok, reviewed} <- Store.fetch_candidate(change.store, evaluated_ref),
         governance when not is_nil(governance) <- reviewed.governance do
      %{
        change
        | state: governance.state,
          ref: evaluated_ref,
          report: report,
          delta: delta
      }
    else
      true -> Change.fail(change, :morph_has_no_changes)
      {:error, reason} -> Change.fail(change, reason)
      _invalid -> Change.fail(change, :candidate_is_not_governed)
    end
  rescue
    _exception -> Change.fail(change, :morph_evaluation_failed)
  catch
    _kind, _reason -> Change.fail(change, :morph_evaluation_failed)
  end

  defp change_set(change, now) do
    ChangeSet.new(%{
      base_activation_receipt: change.activation.activation_receipt,
      base_candidate_ref: change.activation.candidate_ref,
      observed_definition_ref: change.activation.definition_ref,
      observed_authority_epoch: change.activation.authority_epoch,
      observed_evidence_digest: ChangeSet.evidence_digest(change.activation, change.evidence),
      operations: change.operations,
      author_ref: change.actor_ref,
      provenance: %{
        "origin" => "ex_blog.morph",
        "change_surface_digest" => Surface.digest(change.surface),
        "rehearsal_policy" => "ex_blog.protected-routing/v1"
      },
      reason: change.reason,
      created_at: now
    })
  end

  defp compose(change, change_set, now) do
    Composer.compose(change.store, change_set,
      activation: change.activation,
      evidence: change.evidence,
      created_at: now,
      applicability_ceilings: Surface.applicability_ceilings(change.surface, change.mount_ids),
      prompt_token_ceiling: change.surface.prompt_token_ceiling
    )
  end

  defp evaluate_candidate(change, candidate, now) do
    MorphChecker.run(change.store, candidate, MorphPolicy.protected_cases(), issued_at: now)
  end
end
