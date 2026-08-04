defmodule ExBlog.Agent.KineticExtension do
  @moduledoc false

  @behaviour Spectre.Extension

  @impl Spectre.Extension
  defdelegate id(), to: Spectre.Kinetic.Extension

  @impl Spectre.Extension
  defdelegate api_version(), to: Spectre.Kinetic.Extension

  @impl Spectre.Extension
  defdelegate compile(owner, opts), to: Spectre.Kinetic.Extension

  @impl Spectre.Extension
  defdelegate agent_config(config), to: Spectre.Kinetic.Extension

  @impl Spectre.Extension
  defdelegate action_providers(opts), to: Spectre.Kinetic.Extension

  @impl Spectre.Extension
  def action_planner(opts), do: {ExBlog.Agent.KineticPlanner, opts}
end
