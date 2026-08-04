defmodule ExBlog.Storage do
  @moduledoc """
  Small durable term store for the single-node ExBlog runtime.

  The canonical articles remain in Git. DETS keeps only local operational
  state such as Spectre conversations, learned routing examples, the AI budget
  ledger, bounded Git operation history, and OAuth client/token hashes. All
  mutations are serialized by this process and synced before replying to the
  caller. Plaintext OAuth credentials are never passed to this store.
  """

  use GenServer

  @table :ex_blog_runtime_storage

  @type key :: term()
  @type update_result(reply) :: {:put, term(), reply} | {:keep, reply}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec fetch(key()) :: {:ok, term()} | :error
  def fetch(key), do: GenServer.call(__MODULE__, {:fetch, key})

  @spec put(key(), term()) :: :ok | {:error, term()}
  def put(key, value), do: GenServer.call(__MODULE__, {:put, key, value})

  @spec delete(key()) :: :ok | {:error, term()}
  def delete(key), do: GenServer.call(__MODULE__, {:delete, key})

  @spec update(key(), term(), (term() -> update_result(term()))) :: term()
  def update(key, default, function) when is_function(function, 1) do
    GenServer.call(__MODULE__, {:update, key, default, function})
  end

  @doc false
  @spec all() :: [{key(), term()}]
  def all, do: GenServer.call(__MODULE__, :all)

  @doc false
  @spec clear() :: :ok | {:error, term()}
  def clear, do: GenServer.call(__MODULE__, :clear)

  @impl GenServer
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    :ok = File.mkdir_p(Path.dirname(path))

    case :dets.open_file(@table,
           file: String.to_charlist(path),
           type: :set,
           auto_save: 5_000,
           repair: true
         ) do
      {:ok, @table} -> {:ok, %{path: path}}
      {:error, reason} -> {:stop, {:storage_open_failed, path, reason}}
    end
  end

  @impl GenServer
  def handle_call({:fetch, key}, _from, state) do
    reply =
      case :dets.lookup(@table, key) do
        [{^key, value}] -> {:ok, value}
        [] -> :error
      end

    {:reply, reply, state}
  end

  def handle_call({:put, key, value}, _from, state) do
    {:reply, persist({key, value}), state}
  end

  def handle_call({:delete, key}, _from, state) do
    reply =
      case :dets.delete(@table, key) do
        :ok -> :dets.sync(@table)
        {:error, _reason} = error -> error
      end

    {:reply, reply, state}
  end

  def handle_call({:update, key, default, function}, _from, state) do
    current =
      case :dets.lookup(@table, key) do
        [{^key, value}] -> value
        [] -> default
      end

    case function.(current) do
      {:put, next, reply} ->
        case persist({key, next}) do
          :ok -> {:reply, reply, state}
          {:error, reason} -> {:reply, {:error, {:storage_write_failed, reason}}, state}
        end

      {:keep, reply} ->
        {:reply, reply, state}
    end
  end

  def handle_call(:all, _from, state) do
    {:reply, :dets.foldl(&[&1 | &2], [], @table), state}
  end

  def handle_call(:clear, _from, state) do
    reply =
      case :dets.delete_all_objects(@table) do
        :ok -> :dets.sync(@table)
        {:error, _reason} = error -> error
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    _ignored = :dets.sync(@table)
    _ignored = :dets.close(@table)
    :ok
  end

  defp persist(object) do
    case :dets.insert(@table, object) do
      :ok -> :dets.sync(@table)
      {:error, _reason} = error -> error
    end
  end
end
