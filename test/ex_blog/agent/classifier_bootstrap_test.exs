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

  defmodule FakeHostedEmbedding do
    @moduledoc false

    @behaviour Spectre.Classifier.Embedding

    @impl Spectre.Classifier.Embedding
    def load(_model, _opts), do: {:ok, 3}

    @impl Spectre.Classifier.Embedding
    def download(model, opts), do: load(model, opts)

    @impl Spectre.Classifier.Embedding
    def embed("hello world", _opts), do: {:ok, [0.1, 0.2, 0.3]}
    def embed(other, _opts), do: {:error, {:unexpected_hosted_input, other}}
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
    assert Enum.all?(counts, fn {_intent, count} -> count >= 24 end)
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
    assert stats.examples == 456
    assert stats.outputs == [output]

    generated = output |> File.read!() |> Jason.decode!()
    assert length(generated) == 456
    assert generated == Enum.sort_by(generated, &{&1["intent"], dataset_key(&1["text"])})
  end

  test "development classifier training uses the configured local encoder" do
    assert ClassifierConfig.encoder_model() == "intfloat/multilingual-e5-small"

    classifier = Application.fetch_env!(:spectre, :classifier)
    assert classifier[:encoder_model] == ClassifierConfig.encoder_model()
    assert classifier[:embedding_adapter] == ExBlog.Agent.Embedding
    assert classifier[:dataset_path] == "priv/spectre/dataset.json"
    assert classifier[:local_classifier_mode] == :centroid
  end

  test "the shared E5 boundary prefixes both training and query text" do
    assert Embedding.local?()

    assert {:ok, [0.25, 0.75]} =
             Embedding.embed("hello world", ex_fastembed_module: FakeFastembed)
  end

  test "the production-style adapter receives plain text without the E5 prefix" do
    previous = Application.fetch_env!(:ex_blog, :spectre_embedding_adapter)
    Application.put_env(:ex_blog, :spectre_embedding_adapter, FakeHostedEmbedding)

    on_exit(fn -> Application.put_env(:ex_blog, :spectre_embedding_adapter, previous) end)

    refute Embedding.local?()
    assert {:ok, [0.1, 0.2, 0.3]} = Embedding.embed("hello world")

    assert Embedding.identity(ExBlog.Config.get()) ==
             "custom:ExBlog.Agent.ClassifierBootstrapTest.FakeHostedEmbedding"
  end

  test "ExFastembed is excluded from production dependencies and runtime startup" do
    dependency =
      Mix.Project.config()
      |> Keyword.fetch!(:deps)
      |> Enum.find(&(elem(&1, 0) == :ex_fastembed))

    assert {:ex_fastembed, opts} = dependency
    assert Keyword.fetch!(opts, :only) == [:dev, :test]
    refute Keyword.fetch!(opts, :runtime)
  end

  test "the production profile uses OpenRouter and disables every local artifact" do
    production = Config.Reader.read!("config/prod.exs")
    ex_blog = Keyword.fetch!(production, :ex_blog)
    classifier = production |> Keyword.fetch!(:spectre) |> Keyword.fetch!(:classifier)

    assert Keyword.fetch!(ex_blog, :spectre_embedding_adapter) == ExBlog.AI.Embedding
    assert Keyword.fetch!(classifier, :embedding_adapter) == ExBlog.Agent.Embedding
    refute Keyword.fetch!(classifier, :local_classifier_enabled?)
    refute Keyword.fetch!(classifier, :start?)
    refute Keyword.fetch!(classifier, :required?)
    assert Keyword.fetch!(classifier, :artifact_dir) == nil

    dockerfile = File.read!("Dockerfile")
    refute dockerfile =~ "mix spectre.classifier.setup"
    refute dockerfile =~ "COPY --from=builder --chown=exblog:exblog /build/.fastembed_cache"
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
    assert ExBlog.Config.public(ExBlog.Config.get()).models.local_classifier == "disabled"
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
