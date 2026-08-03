defmodule ExBlog.TestLens do
  @moduledoc false

  alias SpectreLens.PageMap
  alias SpectreLens.View

  def open(opts) do
    notify(opts, {:open, opts})
    {:ok, {:lens_runtime, opts}}
  end

  def new_tab({:lens_runtime, opts}, tab_opts) do
    notify(opts, {:new_tab, tab_opts})
    {:ok, {:lens_tab, opts}}
  end

  def look({:lens_tab, opts}, look_opts) do
    notify(opts, {:look, look_opts})
    Keyword.get(opts, :look_result, {:ok, Keyword.fetch!(opts, :view)})
  end

  def zoom_out({:lens_tab, opts}) do
    notify(opts, :zoom_out)

    Keyword.get(
      opts,
      :zoom_out_result,
      {:ok, %PageMap{description: "Header, main content, and footer are present."}}
    )
  end

  def agent_context(%View{} = view, opts), do: SpectreLens.agent_context(view, opts)

  def agent_context(%PageMap{} = page_map, opts),
    do: SpectreLens.agent_context(page_map, opts)

  def close_tab({:lens_tab, opts}) do
    notify(opts, :close_tab)
    :ok
  end

  def close({:lens_runtime, opts}) do
    notify(opts, :close)
    :ok
  end

  defp notify(opts, message) do
    case Keyword.get(opts, :test_pid) do
      pid when is_pid(pid) -> send(pid, {:lens, message})
      _other -> :ok
    end
  end
end
