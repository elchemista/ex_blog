defmodule ExBlog.Agent.ArticleSelections do
  @moduledoc """
  Stores the latest numbered article list shown in one conversation.

  The list is a navigation aid, not canonical content. Only bounded article
  identifiers and labels are persisted; Markdown remains in Git and the content
  index. Resolving a number always re-reads the current article, so a stale list
  cannot resurrect deleted content or bypass the normal status checks.
  """

  alias ExBlog.Storage

  @maximum_entries 250

  @type entry :: %{
          number: pos_integer(),
          lang: String.t(),
          slug: String.t(),
          title: String.t() | nil,
          status: atom() | String.t()
        }

  @doc "Maximum number of articles retained from one displayed list."
  @spec maximum_entries() :: pos_integer()
  def maximum_entries, do: @maximum_entries

  @doc "Replaces the latest numbered list for a conversation."
  @spec remember(term(), [map()]) :: :ok | {:error, term()}
  def remember(conversation_id, articles) when is_list(articles) do
    case identity(conversation_id) do
      nil ->
        :ok

      conversation_id ->
        entries =
          articles
          |> Enum.take(@maximum_entries)
          |> Enum.with_index(1)
          |> Enum.map(fn {article, number} ->
            %{
              number: number,
              lang: field(article, :lang),
              slug: field(article, :slug),
              title: field(article, :title),
              status: field(article, :status)
            }
          end)

        Storage.put(storage_key(conversation_id), entries)
    end
  end

  @doc "Returns the latest bounded list for a conversation."
  @spec recall(term()) :: {:ok, [entry()]} | {:error, :article_list_required}
  def recall(conversation_id) do
    with conversation_id when is_binary(conversation_id) <- identity(conversation_id),
         {:ok, entries} when is_list(entries) <- Storage.fetch(storage_key(conversation_id)) do
      {:ok, entries}
    else
      _missing -> {:error, :article_list_required}
    end
  end

  @doc "Resolves one one-based number from the latest displayed list."
  @spec fetch(term(), pos_integer()) ::
          {:ok, entry()}
          | {:error, :article_list_required | {:article_number_out_of_range, pos_integer()}}
  def fetch(conversation_id, number) when is_integer(number) and number > 0 do
    with {:ok, entries} <- recall(conversation_id) do
      case Enum.at(entries, number - 1) do
        %{number: ^number} = entry -> {:ok, entry}
        _missing -> {:error, {:article_number_out_of_range, number}}
      end
    end
  end

  def fetch(_conversation_id, number), do: {:error, {:article_number_out_of_range, number}}

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp identity(nil), do: nil
  defp identity(value) when is_binary(value), do: non_blank(value)

  defp identity(value) when is_atom(value) or is_number(value),
    do: value |> to_string() |> non_blank()

  defp identity(_value), do: nil

  defp non_blank(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp storage_key(conversation_id), do: {:article_selections, conversation_id}
end
