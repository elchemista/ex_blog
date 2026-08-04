defmodule Mix.Tasks.ExBlog.Spectre.Dataset.Build do
  @moduledoc """
  Validates ExBlog's hand-written routing corpus and prepares it for training.

  The canonical dataset is versioned at `priv/spectre/dataset.json`, making it
  available to exact semantic-cache lookup in both source checkouts and OTP
  releases. This task validates labels against the actual Agent definition,
  rejects duplicate or non-English examples, checks minimum intent coverage,
  and writes the normalized training copy consumed by Spectre.

      mix ex_blog.spectre.dataset.build
      mix ex_blog.spectre.dataset.build --check
      mix ex_blog.spectre.dataset.build --output tmp/dataset.json
  """

  use Mix.Task

  @shortdoc "Validate and prepare the ExBlog Spectre dataset"

  @default_source "priv/spectre/dataset.json"
  @default_output "training/dataset.json"
  @minimum_examples_per_intent 12
  @switches [source: :string, output: :keep, check: :boolean]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok | no_return()
  def run(argv) do
    Mix.Task.run("app.config")

    {opts, args, invalid} = OptionParser.parse(argv, strict: @switches)

    if invalid != [] or args != [] do
      Mix.raise("invalid dataset build arguments: #{inspect(args ++ invalid)}")
    end

    source = Keyword.get(opts, :source, @default_source)

    outputs =
      cond do
        Keyword.get(opts, :check, false) -> []
        Keyword.get_values(opts, :output) == [] -> [@default_output]
        true -> Keyword.get_values(opts, :output)
      end

    case build(source, outputs) do
      {:ok, stats} ->
        Mix.shell().info("ExBlog Spectre dataset ready")
        Mix.shell().info(Jason.encode!(stats, pretty: true))
        :ok

      {:error, reason} ->
        Mix.raise("ExBlog Spectre dataset build failed: #{inspect(reason)}")
    end
  end

  @doc false
  @spec build(String.t(), [String.t()]) :: {:ok, map()} | {:error, term()}
  def build(source, outputs) when is_binary(source) and is_list(outputs) do
    allowed_labels = classifier_labels()

    with {:ok, rows} <- read_rows(source, allowed_labels),
         :ok <- validate_unique_text(rows),
         :ok <- validate_coverage(rows, allowed_labels),
         :ok <- write_outputs(outputs, rows) do
      {:ok,
       %{
         source: source,
         outputs: Enum.uniq(outputs),
         examples: length(rows),
         intents: rows |> Enum.frequencies_by(& &1["intent"]) |> Enum.sort() |> Map.new()
       }}
    end
  end

  def build(_source, _outputs), do: {:error, :invalid_build_arguments}

  @spec read_rows(String.t(), MapSet.t(String.t())) :: {:ok, [map()]} | {:error, term()}
  defp read_rows(path, allowed_labels) do
    with {:ok, bytes} <- File.read(path),
         {:ok, decoded} <- Jason.decode(bytes),
         true <- is_list(decoded) || {:error, {:invalid_dataset, path}} do
      normalize_rows(decoded, path, allowed_labels)
    end
  end

  @spec normalize_rows([term()], String.t(), MapSet.t(String.t())) ::
          {:ok, [map()]} | {:error, term()}
  defp normalize_rows(rows, path, allowed_labels) do
    rows
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {row, line}, {:ok, normalized_rows} ->
      normalize_dataset_row(row, line, path, allowed_labels, normalized_rows)
    end)
    |> reverse_and_sort()
  end

  @spec normalize_dataset_row(term(), pos_integer(), String.t(), MapSet.t(String.t()), [map()]) ::
          {:cont, {:ok, [map()]}} | {:halt, {:error, term()}}
  defp normalize_dataset_row(row, line, path, allowed_labels, rows) do
    case normalize_row(row, allowed_labels) do
      {:ok, normalized} -> {:cont, {:ok, [normalized | rows]}}
      {:error, reason} -> {:halt, {:error, {:invalid_row, path, line, reason}}}
    end
  end

  @spec normalize_row(term(), MapSet.t(String.t())) :: {:ok, map()} | {:error, term()}
  defp normalize_row(%{"text" => text} = row, allowed_labels) when is_binary(text) do
    intent = Map.get(row, "intent", Map.get(row, "label"))
    language = row |> Map.get("language", "en") |> normalize_value()
    text = text |> String.replace(~r/\s+/u, " ") |> String.trim()
    intent = normalize_intent(intent)

    cond do
      text == "" -> {:error, :blank_text}
      intent == nil -> {:error, :missing_intent}
      language != "en" -> {:error, {:non_english_example, language}}
      not MapSet.member?(allowed_labels, intent) -> {:error, {:unknown_intent, intent}}
      true -> {:ok, %{"text" => text, "intent" => intent, "language" => "en"}}
    end
  end

  defp normalize_row(_row, _allowed_labels), do: {:error, :expected_text_and_intent}

  @spec validate_unique_text([map()]) :: :ok | {:error, term()}
  defp validate_unique_text(rows) do
    result =
      Enum.reduce_while(rows, %{}, fn row, seen ->
        key = dataset_key(row["text"])

        case Map.fetch(seen, key) do
          {:ok, previous} ->
            {:halt, {:duplicate, row["text"], previous, row["intent"]}}

          :error ->
            {:cont, Map.put(seen, key, row["intent"])}
        end
      end)

    case result do
      {:duplicate, text, previous, current} ->
        {:error, {:duplicate_text, text, previous, current}}

      _no_duplicate ->
        :ok
    end
  end

  @spec validate_coverage([map()], MapSet.t(String.t())) :: :ok | {:error, term()}
  defp validate_coverage(rows, allowed_labels) do
    counts = Enum.frequencies_by(rows, & &1["intent"])

    missing_or_small =
      allowed_labels
      |> Enum.map(&{&1, Map.get(counts, &1, 0)})
      |> Enum.filter(fn {_label, count} -> count < @minimum_examples_per_intent end)
      |> Enum.sort()

    if missing_or_small == [],
      do: :ok,
      else: {:error, {:insufficient_intent_coverage, missing_or_small}}
  end

  @spec write_outputs([String.t()], [map()]) :: :ok | {:error, term()}
  defp write_outputs(outputs, rows) do
    encoded = Jason.encode!(rows, pretty: true) <> "\n"

    outputs
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn path, :ok ->
      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- File.write(path, encoded) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, {:write_failed, path, reason}}}
      end
    end)
  end

  @spec classifier_labels() :: MapSet.t(String.t())
  defp classifier_labels do
    ExBlog.Agent
    |> Spectre.Definition.rules()
    |> Enum.map(&Spectre.Rule.new/1)
    |> Enum.filter(&(:classifier in &1.via))
    |> MapSet.new(&(to_string(&1.label) |> String.upcase()))
  end

  @spec dataset_key(String.t()) :: String.t()
  defp dataset_key(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end

  defp normalize_intent(value) when is_binary(value),
    do: value |> String.trim() |> String.upcase()

  defp normalize_intent(_value), do: nil

  defp normalize_value(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  defp normalize_value(value), do: value

  defp reverse_and_sort({:ok, rows}) do
    rows = rows |> Enum.reverse() |> Enum.sort_by(&{&1["intent"], dataset_key(&1["text"])})
    {:ok, rows}
  end

  defp reverse_and_sort({:error, _reason} = error), do: error
end
