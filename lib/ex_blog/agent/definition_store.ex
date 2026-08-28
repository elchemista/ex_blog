defmodule ExBlog.Agent.DefinitionStore do
  @moduledoc """
  Durable immutable Definition Store for the editorial Agent.

  Spectre owns artifact encoding, content addressing, publication receipts,
  and read-back verification. This adapter only gives those opaque bytes an
  immutable namespace in ExBlog's synced DETS store. Identical writes are
  idempotent; attempting to replace bytes under an existing Ref fails closed.
  """

  @behaviour Spectre.Definition.Store

  alias ExBlog.Storage

  @identity "ex-blog-agent-definitions/v1"
  @namespace :spectre_definition_store

  @doc "Returns the Definition Store configuration passed to Spectre Instances."
  @spec config() :: Spectre.Definition.Store.config()
  def config, do: __MODULE__

  @impl Spectre.Definition.Store
  def identity(_opts), do: @identity

  @impl Spectre.Definition.Store
  def durability(_opts), do: :durable

  @impl Spectre.Definition.Store
  def get(key, _opts) when is_binary(key) do
    case Storage.fetch(storage_key(key)) do
      {:ok, encoded} when is_binary(encoded) -> {:ok, encoded}
      :error -> :not_found
      {:ok, _invalid} -> {:error, {:invalid_definition_artifact, key}}
    end
  end

  @impl Spectre.Definition.Store
  def put(key, encoded, _opts) when is_binary(key) and is_binary(encoded) do
    Storage.update(storage_key(key), :missing, fn
      :missing ->
        {:put, encoded, {:ok, :created}}

      ^encoded ->
        {:keep, {:ok, :existing}}

      _different ->
        {:keep, {:error, {:immutable_conflict, key}}}
    end)
  end

  defp storage_key(key), do: {@namespace, key}
end
