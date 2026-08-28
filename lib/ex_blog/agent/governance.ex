defmodule ExBlog.Agent.Governance do
  @moduledoc """
  Publishes and activates the compiled editorial Definition at boot.

  Morph can only create a governed Candidate from an active, immutable source
  Definition. This process establishes that source under a durable Definition
  Store, keeps the Subject-scoped Instance live for Studio, and re-establishes
  the bootstrap activation if the in-memory Instance restarts.

  The granted runtime-Skill authority is deliberately narrow: Morph may mount
  or replace a reply-only Skill within the Agent scope and a 4,096-token total
  prompt ceiling. Proposals still require human approval and neither this
  process nor the Pulse bridge approves or activates a proposed Candidate.
  """

  use GenServer

  require Logger

  alias ExBlog.Agent.{DefinitionStore, MorphPolicy}
  alias Spectre.Definition
  alias Spectre.Definition.Resolver
  alias Spectre.Definition.Store
  alias Spectre.Instance.Activation

  @supervisor ExBlog.SpectreSupervisor
  @subject "blog-operations"
  @publisher_ref "publisher:ex-blog"
  @provenance_refs ["application:ex-blog"]
  @prompt_token_ceiling 4_096
  @retry_ms 1_000

  @type state :: %{
          pid: pid() | nil,
          monitor_ref: reference() | nil,
          candidate_ref: term() | nil,
          definition_ref: String.t() | nil
        }

  @doc "Starts the Definition publication and activation owner."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Starts or returns the active editorial Agent Instance."
  @spec ensure() :: {:ok, pid()} | {:error, term()}
  def ensure, do: GenServer.call(__MODULE__, :ensure, 30_000)

  @doc "Subject used by Studio when addressing Morph proposals."
  @spec subject() :: String.t()
  def subject, do: @subject

  @impl GenServer
  def init(_opts) do
    case provision() do
      {:ok, provisioned} ->
        log_ready(provisioned)
        {:ok, monitor(provisioned)}

      {:error, reason} ->
        {:stop, {:agent_governance_boot_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call(:ensure, _from, %{pid: pid} = state) when is_pid(pid) do
    if Process.alive?(pid) do
      {:reply, {:ok, pid}, state}
    else
      reprovision_reply(state)
    end
  end

  def handle_call(:ensure, _from, state), do: reprovision_reply(state)

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{monitor_ref: ref} = state) do
    Logger.warning("agent_definition instance_down reason=#{inspect(reason)}")
    Process.send_after(self(), :reprovision, @retry_ms)
    {:noreply, %{state | pid: nil, monitor_ref: nil}}
  end

  def handle_info(:reprovision, state) do
    case provision() do
      {:ok, provisioned} ->
        log_ready(provisioned)
        {:noreply, state |> demonitor() |> Map.merge(monitor(provisioned))}

      {:error, reason} ->
        Logger.error("agent_definition reprovision_failed reason=#{inspect(reason)}")
        Process.send_after(self(), :reprovision, @retry_ms)
        {:noreply, %{state | pid: nil, monitor_ref: nil}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp reprovision_reply(state) do
    case provision() do
      {:ok, provisioned} ->
        log_ready(provisioned)
        next = state |> demonitor() |> Map.merge(monitor(provisioned))
        {:reply, {:ok, provisioned.pid}, next}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | pid: nil, monitor_ref: nil}}
    end
  end

  defp provision do
    started_at = System.monotonic_time()
    store = DefinitionStore.config()
    authority = morph_authority()

    with {:ok, canonical} <- Definition.canonical(ExBlog.Agent),
         {:ok, manifest} <-
           Definition.manifest(ExBlog.Agent,
             authority_requests: authority,
             authority_ceiling: authority,
             owner_modules: [ExBlog.Agent.Works.SyncAndVerify],
             evaluation_corpus_digest: MorphPolicy.protected_corpus_digest(),
             publisher_ref: @publisher_ref,
             provenance_refs: @provenance_refs
           ),
         {:ok, receipt} <- Store.publish(store, canonical, manifest),
         {:ok, candidate_ref} <-
           Resolver.bootstrap_candidate(store, receipt.definition_ref,
             source: :compiled,
             provenance_refs: @provenance_refs
           ),
         {:ok, pid} <-
           Spectre.ensure_instance(@supervisor, ExBlog.Agent, @subject,
             definition_store: store,
             idle: false
           ),
         {:ok, activation} <- ensure_activation(pid, candidate_ref) do
      {:ok,
       %{
         pid: pid,
         monitor_ref: nil,
         candidate_ref: candidate_ref,
         definition_ref: to_string(activation.definition_ref),
         generation: activation.generation,
         duration_ms: elapsed_ms(started_at)
       }}
    end
  rescue
    exception -> {:error, {:exception, Exception.message(exception)}}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp ensure_activation(pid, candidate_ref) do
    case Spectre.activation(pid) do
      %Activation{} = activation ->
        {:ok, activation}

      nil ->
        Spectre.activate(pid, candidate_ref,
          expected_generation: 0,
          provenance: %{
            source: :trusted_host,
            publisher: @publisher_ref,
            reason: :compiled_bootstrap
          }
        )
    end
  end

  defp morph_authority do
    capabilities = [
      Spectre.Skill.Runtime.capability(:mount),
      Spectre.Skill.Runtime.capability(:replace)
    ]

    %{
      open_capabilities: capabilities,
      prompt_budget_classes: [:small, :standard],
      limits: %{max_tokens: @prompt_token_ceiling}
    }
  end

  defp monitor(%{pid: pid} = state) do
    Map.put(state, :monitor_ref, Process.monitor(pid))
  end

  defp demonitor(%{monitor_ref: ref} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    %{state | monitor_ref: nil}
  end

  defp demonitor(state), do: state

  defp log_ready(state) do
    Logger.info(
      "agent_definition ready definition_ref=#{state.definition_ref} " <>
        "generation=#{state.generation} subject=#{@subject} duration_ms=#{state.duration_ms}"
    )
  end

  defp elapsed_ms(started_at) do
    System.monotonic_time()
    |> Kernel.-(started_at)
    |> System.convert_time_unit(:native, :millisecond)
  end
end
