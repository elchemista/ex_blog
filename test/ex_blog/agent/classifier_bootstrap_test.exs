defmodule ExBlog.Agent.ClassifierBootstrapTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Agent.ClassifierConfig
  alias ExBlog.Agent.Embedding
  alias ExBlog.Agent.LocalClassifier
  alias ExBlog.Agent.SemanticCache
  alias Mix.Tasks.ExBlog.Spectre.Dataset.Build

  @dataset_path "priv/spectre/dataset.json"

  defmodule FakeFastembed do
    @moduledoc false

    def load(_model), do: {:ok, 2}
    def embed_text(["query: hello world"]), do: {:ok, [[0.25, 0.75]]}
    def embed_text(other), do: {:error, {:unexpected_embedding_input, other}}
  end

  test "the checked-in corpus covers every classifier-visible Agent intent" do
    rows = @dataset_path |> File.read!() |> Jason.decode!()

    expected_labels =
      ExBlog.Agent
      |> Spectre.Definition.rules()
      |> Enum.map(&Spectre.Rule.new/1)
      |> Enum.filter(&(:classifier in &1.via))
      |> MapSet.new(&(to_string(&1.label) |> String.upcase()))

    counts = Enum.frequencies_by(rows, & &1["intent"])

    assert MapSet.new(Map.keys(counts)) == expected_labels
    assert Enum.all?(counts, fn {_intent, count} -> count >= 12 end)
    assert Enum.all?(rows, &(&1["language"] == "en"))
  end

  test "the dataset task validates and writes a deterministic training corpus" do
    output =
      Path.join(
        System.tmp_dir!(),
        "ex-blog-spectre-dataset-#{System.unique_integer([:positive, :monotonic])}.json"
      )

    on_exit(fn -> File.rm(output) end)

    assert {:ok, stats} = Build.build(@dataset_path, [output])
    assert stats.examples == 204
    assert stats.outputs == [output]

    generated = output |> File.read!() |> Jason.decode!()
    assert length(generated) == 204
    assert generated == Enum.sort_by(generated, &{&1["intent"], dataset_key(&1["text"])})
  end

  test "the classifier and semantic cache share one local encoder model" do
    assert ClassifierConfig.encoder_model() == "intfloat/multilingual-e5-small"

    classifier = Application.fetch_env!(:spectre, :classifier)
    assert classifier[:encoder_model] == ClassifierConfig.encoder_model()
    assert classifier[:embedding_adapter] == ExBlog.Agent.Embedding
    assert classifier[:dataset_path] == "priv/spectre/dataset.json"
    assert classifier[:local_classifier_mode] == :centroid
  end

  test "the shared E5 boundary prefixes both training and query text" do
    assert {:ok, [0.25, 0.75]} =
             Embedding.embed("hello world", ex_fastembed_module: FakeFastembed)
  end

  test "semantic cache warmup succeeds even before generated vectors exist" do
    assert {:ok, vector_count} = SemanticCache.warm()
    assert vector_count >= 0
  end

  test "the app-owned adapter can disable local inference without disabling fallbacks" do
    previous = Application.fetch_env!(:spectre, :classifier)

    Application.put_env(
      :spectre,
      :classifier,
      Keyword.put(previous, :local_classifier_enabled?, false)
    )

    on_exit(fn -> Application.put_env(:spectre, :classifier, previous) end)

    assert {:error, :local_classifier_disabled} = LocalClassifier.classify("list articles", [])
  end

  test "a required production-style runtime fails closed without its dataset" do
    previous = Application.fetch_env!(:spectre, :classifier)

    Application.put_env(
      :spectre,
      :classifier,
      previous
      |> Keyword.put(:dataset_path, "tmp/missing-spectre-dataset.json")
      |> Keyword.put(:required?, true)
    )

    on_exit(fn -> Application.put_env(:spectre, :classifier, previous) end)

    assert_raise ExBlog.ConfigError, ~r/Spectre classifier dataset is missing/, fn ->
      ClassifierConfig.validate_required_sources!()
    end
  end

  defp dataset_key(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end
end
