defmodule ExBlog.Agent.KineticPackage do
  @moduledoc false

  @behaviour Spectre.Stack.Installable

  alias ExBlog.Agent.KineticExtension

  @impl Spectre.Stack.Installable
  def manifest do
    :kinetic = KineticExtension.id()

    Spectre.Kinetic.manifest()
    |> Keyword.put(:agent_extensions, [KineticExtension])
    |> Keyword.update(:metadata, %{planner_fallback: :llm}, fn metadata ->
      Map.put(metadata, :planner_fallback, :llm)
    end)
  end

  @impl Spectre.Stack.Installable
  def compile(opts, block, caller), do: Spectre.Kinetic.compile(opts, block, caller)
end
