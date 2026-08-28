defmodule ExBlog.Agent.Instance do
  @moduledoc """
  Single Subject-scoped Agent Instance owning the blog's operational loops.

  Conversational turns keep using the module-based Spectre runtime; the
  Instance exists so `work(...)` route handlers can start durable Work loops
  and status routes can read their committed views. It is supervised under
  `ExBlog.SpectreSupervisor` and holds only in-memory operational state: a
  restart loses running verification loops but never blog content.
  """

  @supervisor ExBlog.SpectreSupervisor
  @doc "Name of the dynamic supervisor declared in the application tree."
  @spec supervisor() :: module()
  def supervisor, do: @supervisor

  @doc "Starts or reuses the blog's Agent Instance."
  @spec ensure() :: {:ok, pid()} | {:error, term()}
  def ensure do
    case Process.whereis(ExBlog.Agent.Governance) do
      pid when is_pid(pid) ->
        ExBlog.Agent.Governance.ensure()

      nil ->
        # Keep isolated callers usable when the application supervision tree is
        # intentionally absent (for example, compile-time tooling).
        Spectre.ensure_instance(
          @supervisor,
          ExBlog.Agent,
          ExBlog.Agent.Governance.subject()
        )
    end
  end

  @doc "Adds `instance_pid` to Spectre call options when the Instance is available."
  @spec put_instance(keyword()) :: keyword()
  def put_instance(opts) when is_list(opts) do
    case ensure() do
      {:ok, pid} -> Keyword.put_new(opts, :instance_pid, pid)
      {:error, _reason} -> opts
    end
  end
end
