defmodule ExBlog.Content.Bootstrap do
  @moduledoc false

  use GenServer

  require Logger

  alias ExBlog.Config
  alias ExBlog.Content.Asset
  alias ExBlog.Content.Git

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    started_at = System.monotonic_time()

    with {:ok, commit} <- Git.ensure_checkout(opts),
         :ok <- Asset.restore_from_repository(opts) do
      Logger.info("content_checkout ready commit=#{commit} duration_ms=#{elapsed_ms(started_at)}")

      {:ok, %{commit: commit}}
    else
      {:error, reason} ->
        Logger.error(
          "content_checkout boot_failed code=#{error_code(reason)} " <>
            "reason=#{inspect(safe_reason(reason))} duration_ms=#{elapsed_ms(started_at)}"
        )

        {:stop, {:content_boot_failed, reason}}
    end
  end

  defp safe_reason(reason) do
    reason
    |> inspect(limit: 20, printable_limit: 1_000)
    |> Config.redact()
  end

  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp error_code(reason) when is_tuple(reason) and tuple_size(reason) > 0,
    do: reason |> elem(0) |> error_code()

  defp error_code(_reason), do: "unknown"

  defp elapsed_ms(started_at) do
    started_at
    |> then(&(System.monotonic_time() - &1))
    |> System.convert_time_unit(:native, :millisecond)
  end
end
