defmodule ExBlog.Agent.ClassifierConfig do
  @moduledoc """
  Resolves the versioned dataset and generated classifier artifacts.

  ExBlog keeps the hand-written corpus in `priv/spectre/dataset.json`, so it is
  available both from a source checkout and from an OTP release. The generated
  classifier and its vectorized semantic mirror live beside it under
  `priv/spectre/classifier`; those files are reproducible build artifacts and
  are created by `mix spectre.classifier.setup`.

  Keeping path resolution here avoids a common release bug: a relative
  `priv/...` path points at the process working directory, while
  `:code.priv_dir/1` points at the application's actual release directory.
  """

  require Logger

  @encoder_model "intfloat/multilingual-e5-small"
  @dataset_relative_path "spectre/dataset.json"
  @artifact_relative_path "spectre/classifier"

  @doc "Returns the encoder used by both the local classifier and semantic search."
  @spec encoder_model() :: String.t()
  def encoder_model, do: @encoder_model

  @doc "Returns the dataset path currently installed in Spectre configuration."
  @spec dataset_path() :: String.t()
  def dataset_path do
    classifier_options()
    |> Keyword.get(:dataset_path, source_dataset_path())
  end

  @doc "Returns the classifier artifact directory currently installed in Spectre."
  @spec artifact_dir() :: String.t()
  def artifact_dir do
    classifier_options()
    |> Keyword.get(:artifact_dir, source_artifact_dir())
  end

  @doc "Returns the tracked dataset path for a normal source checkout."
  @spec source_dataset_path() :: String.t()
  def source_dataset_path, do: Path.expand("priv/#{@dataset_relative_path}")

  @doc "Returns the generated artifact path for a normal source checkout."
  @spec source_artifact_dir() :: String.t()
  def source_artifact_dir, do: Path.expand("priv/#{@artifact_relative_path}")

  @doc "Resolves the tracked dataset inside an assembled OTP release."
  @spec release_dataset_path() :: String.t()
  def release_dataset_path, do: release_priv_path(@dataset_relative_path)

  @doc "Resolves generated classifier artifacts inside an assembled OTP release."
  @spec release_artifact_dir() :: String.t()
  def release_artifact_dir, do: release_priv_path(@artifact_relative_path)

  @doc "Returns whether trained local routing is enabled for this runtime."
  @spec local_enabled?() :: boolean()
  def local_enabled? do
    classifier_options()
    |> Keyword.get(:local_classifier_enabled?, true)
  end

  @doc "Returns whether the warm classifier process should be supervised."
  @spec start?() :: boolean()
  def start?, do: Keyword.get(classifier_options(), :start?, true)

  @doc "Builds the options passed to the supervised Spectre classifier process."
  @spec child_options() :: keyword()
  def child_options do
    classifier_options()
    |> Keyword.delete(:start?)
    |> Keyword.delete(:local_classifier_enabled?)
    |> Keyword.delete(:dataset_path)
  end

  @doc "Logs privacy-safe boot diagnostics for the corpus and trained artifact."
  @spec log_boot_status() :: :ok
  def log_boot_status do
    log_path(:dataset, dataset_path())

    if start?() do
      log_path(:classifier, Path.join(artifact_dir(), "classifier.etf"))
    else
      Logger.info("spectre_classifier disabled")
    end

    :ok
  end

  @doc "Fails a required runtime before it serves without its versioned corpus."
  @spec validate_required_sources!() :: :ok
  def validate_required_sources! do
    required? = Keyword.get(classifier_options(), :required?, false)

    if required? and not File.regular?(dataset_path()) do
      raise ExBlog.ConfigError,
        message: "Spectre classifier dataset is missing: #{dataset_path()}"
    end

    :ok
  end

  @spec classifier_options() :: keyword()
  defp classifier_options, do: Application.get_env(:spectre, :classifier, [])

  @spec release_priv_path(String.t()) :: String.t()
  defp release_priv_path(relative_path) do
    case :code.priv_dir(:ex_blog) do
      path when is_list(path) -> path |> List.to_string() |> Path.join(relative_path)
      {:error, _reason} -> Path.expand(Path.join("priv", relative_path))
    end
  end

  @spec log_path(atom(), String.t()) :: :ok
  defp log_path(kind, path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} ->
        Logger.info("spectre_#{kind} ready path=#{path} bytes=#{size}")

      {:ok, %{type: type}} ->
        Logger.warning("spectre_#{kind} invalid path=#{path} type=#{inspect(type)}")

      {:error, reason} ->
        Logger.warning("spectre_#{kind} missing path=#{path} reason=#{inspect(reason)}")
    end

    :ok
  end
end
