defmodule ExBlog.Content.Asset do
  @moduledoc """
  Safe write boundary for administrator-supplied article images.

  Files are addressed by their SHA-256 digest, so repeated Telegram uploads are
  idempotent and no user-controlled filename reaches the filesystem. The image
  type is determined from magic bytes rather than Telegram metadata; SVG and
  arbitrary documents are intentionally rejected.

  The public copy lives in `priv/static/images/articles`, which Phoenix exposes
  below `/images`, and a runtime mirror lives on the configured data volume.
  Once the administrator approves the draft, the same validated image is staged
  under `assets/images/articles` in the content repository and committed with
  the Markdown file. Clone and sync restore Git-managed assets into both runtime
  locations. Tests can pass `:root` to isolate the upload store.
  """

  alias ExBlog.Config

  @max_bytes 10 * 1_024 * 1_024
  @public_prefix "/images/articles"
  @repository_prefix Path.join(["assets", "images", "articles"])

  @type stored :: %{
          public_path: String.t(),
          filename: String.t(),
          digest: String.t(),
          size: non_neg_integer(),
          created?: boolean()
        }

  @doc "Validates and stores one raster image under Phoenix static assets."
  @spec store(binary(), keyword()) :: {:ok, stored()} | {:error, term()}
  def store(bytes, opts \\ [])

  def store(bytes, opts) when is_binary(bytes) and is_list(opts) do
    with :ok <- validate_size(bytes),
         {:ok, extension} <- extension(bytes),
         root <- asset_root(opts),
         :ok <- File.mkdir_p(root) do
      digest = sha256(bytes)
      filename = "#{digest}.#{extension}"
      target = Path.join(root, filename)

      with {:ok, created?} <- write_once(target, bytes),
           :ok <- mirror(filename, bytes, opts) do
        {:ok,
         %{
           public_path: Path.join(@public_prefix, filename),
           filename: filename,
           digest: digest,
           size: byte_size(bytes),
           created?: created?
         }}
      end
    end
  end

  def store(_bytes, _opts), do: {:error, :invalid_image_bytes}

  @doc "Maximum accepted Telegram image size in bytes."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc """
  Copies a content-addressed Telegram cover into the content checkout.

  Non-Telegram cover URLs and legacy root-relative paths are left alone. A
  recognized `/images/articles/<sha256>.<ext>` path must resolve to validated
  bytes, either already in Git or in the upload store, before the caller may
  commit the article that references it.
  """
  @spec stage_for_git(String.t() | nil, keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def stage_for_git(cover, opts \\ []) when is_list(opts) do
    case repository_asset_path(cover) do
      {:ok, filename, relative_path} -> stage_asset(filename, relative_path, opts)
      :external_or_legacy -> {:ok, []}
    end
  end

  @doc "Restores validated Git-managed covers into durable and public storage."
  @spec restore_from_repository(keyword()) :: :ok | {:error, term()}
  def restore_from_repository(opts \\ []) when is_list(opts) do
    config = Keyword.get(opts, :config, ExBlog.Config.get())

    source =
      Keyword.get(
        opts,
        :repository_root,
        Path.join(Config.repository_path(config), @repository_prefix)
      )
      |> Path.expand()

    destinations =
      [
        Keyword.get(opts, :durable_root, durable_root(config)),
        Keyword.get(opts, :root, static_root())
      ]
      |> Enum.map(&Path.expand/1)
      |> Enum.uniq()

    if File.dir?(source), do: restore_repository_directory(source, destinations), else: :ok
  end

  @doc "Restores durable article images into Phoenix's release-local static tree."
  @spec restore_static!(keyword()) :: :ok
  def restore_static!(opts \\ []) when is_list(opts) do
    source = Keyword.get(opts, :source_root, durable_root()) |> Path.expand()
    target = Keyword.get(opts, :root, static_root()) |> Path.expand()

    File.mkdir_p!(source)
    File.mkdir_p!(target)

    source
    |> File.ls!()
    |> Enum.filter(&asset_filename?/1)
    |> Enum.each(&restore_file!(source, target, &1))

    :ok
  end

  defp validate_size(<<>>), do: {:error, :empty_image}

  defp validate_size(bytes) do
    if byte_size(bytes) <= @max_bytes, do: :ok, else: {:error, :image_too_large}
  end

  defp extension(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: {:ok, "jpg"}

  defp extension(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>),
    do: {:ok, "png"}

  defp extension(<<"GIF87a", _rest::binary>>), do: {:ok, "gif"}
  defp extension(<<"GIF89a", _rest::binary>>), do: {:ok, "gif"}
  defp extension(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: {:ok, "webp"}
  defp extension(_bytes), do: {:error, :unsupported_image_format}

  defp asset_root(opts) do
    opts
    |> Keyword.get_lazy(:root, &static_root/0)
    |> Path.expand()
  end

  defp mirror(filename, bytes, opts) when is_list(opts) do
    if Keyword.has_key?(opts, :root) do
      :ok
    else
      root = durable_root()

      with :ok <- File.mkdir_p(root),
           {:ok, _created?} <- write_once(Path.join(root, filename), bytes) do
        :ok
      end
    end
  end

  defp write_once(target, bytes) do
    case File.lstat(target) do
      {:ok, %File.Stat{type: :regular}} ->
        case File.read(target) do
          {:ok, ^bytes} -> {:ok, false}
          {:ok, _different} -> {:error, :asset_digest_conflict}
          {:error, reason} -> {:error, {:asset_read_failed, reason}}
        end

      {:error, :enoent} ->
        temporary = target <> ".#{System.unique_integer([:positive, :monotonic])}.tmp"

        try do
          with :ok <- File.write(temporary, bytes, [:binary, :exclusive]),
               :ok <- File.rename(temporary, target),
               :ok <- File.chmod(target, 0o644) do
            {:ok, true}
          end
        after
          _ignored = File.rm(temporary)
        end

      {:ok, _unsafe_type} ->
        {:error, :unsafe_asset_target}

      {:error, reason} ->
        {:error, {:asset_stat_failed, reason}}
    end
  end

  defp sha256(bytes) do
    :crypto.hash(:sha256, bytes)
    |> Base.encode16(case: :lower)
  end

  defp static_root, do: Application.app_dir(:ex_blog, "priv/static/images/articles")
  defp durable_root, do: durable_root(ExBlog.Config.get())

  defp durable_root(config),
    do: Path.join([config.data_dir, "assets", "images", "articles"])

  defp asset_filename?(filename) do
    Regex.match?(~r/^[a-f0-9]{64}\.(?:jpg|png|gif|webp)$/u, filename)
  end

  defp repository_asset_path(nil), do: :external_or_legacy

  defp repository_asset_path(@public_prefix <> "/" <> filename) do
    if asset_filename?(filename) do
      {:ok, filename, Path.join(@repository_prefix, filename)}
    else
      :external_or_legacy
    end
  end

  defp repository_asset_path(_cover), do: :external_or_legacy

  defp stage_asset(filename, relative_path, opts) do
    config = Keyword.get(opts, :config, ExBlog.Config.get())
    checkout = Config.repository_path(config)
    target = Path.expand(relative_path, checkout)
    expected_root = Path.expand(@repository_prefix, checkout)

    if String.starts_with?(target, expected_root <> "/"),
      do: stage_safe_asset(filename, relative_path, target, config, opts),
      else: {:error, :unsafe_cover_asset_path}
  end

  defp stage_safe_asset(filename, relative_path, target, config, opts) do
    case read_regular(target) do
      {:ok, bytes} -> validate_staged_asset(filename, relative_path, bytes)
      {:error, :enoent} -> copy_staged_asset(filename, relative_path, target, config, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_staged_asset(filename, relative_path, bytes) do
    with :ok <- validate_asset(filename, bytes), do: {:ok, [relative_path]}
  end

  defp copy_staged_asset(filename, relative_path, target, config, opts) do
    source_root = Keyword.get(opts, :source_root, durable_root(config)) |> Path.expand()
    source = Path.join(source_root, filename)

    with {:ok, bytes} <- read_regular(source),
         :ok <- validate_asset(filename, bytes),
         :ok <- File.mkdir_p(Path.dirname(target)),
         {:ok, _created?} <- write_once(target, bytes) do
      {:ok, [relative_path]}
    else
      {:error, :enoent} -> {:error, :cover_asset_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp restore_repository_directory(source, destinations) do
    with {:ok, filenames} <- File.ls(source) do
      filenames
      |> Enum.filter(&asset_filename?/1)
      |> restore_repository_files(source, destinations)
    end
  end

  defp restore_repository_files(filenames, source, destinations) do
    Enum.reduce_while(filenames, :ok, fn filename, :ok ->
      case restore_repository_file(source, destinations, filename) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp restore_repository_file(source, destinations, filename) do
    with {:ok, bytes} <- read_regular(Path.join(source, filename)),
         :ok <- validate_asset(filename, bytes) do
      restore_destinations(destinations, filename, bytes)
    end
  end

  defp restore_destinations(destinations, filename, bytes) do
    Enum.reduce_while(destinations, :ok, fn destination, :ok ->
      case restore_destination(destination, filename, bytes) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp restore_destination(destination, filename, bytes) do
    with :ok <- File.mkdir_p(destination),
         {:ok, _created?} <- write_once(Path.join(destination, filename), bytes) do
      :ok
    end
  end

  defp validate_asset(filename, bytes) do
    expected_digest = Path.rootname(filename)
    expected_extension = filename |> Path.extname() |> String.trim_leading(".")

    with :ok <- validate_size(bytes),
         {:ok, ^expected_extension} <- extension(bytes),
         true <- sha256(bytes) == expected_digest do
      :ok
    else
      _invalid -> {:error, :invalid_content_addressed_asset}
    end
  end

  defp read_regular(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} -> File.read(path)
      {:ok, _unsafe_type} -> {:error, :unsafe_asset_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp restore_file!(source, target, filename) do
    with {:ok, bytes} <- read_regular(Path.join(source, filename)),
         :ok <- validate_asset(filename, bytes) do
      File.write!(Path.join(target, filename), bytes, [:binary])
    else
      {:error, _reason} -> raise ArgumentError, "invalid durable article asset: #{filename}"
    end
  end
end
