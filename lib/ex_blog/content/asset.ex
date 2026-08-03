defmodule ExBlog.Content.Asset do
  @moduledoc """
  Safe write boundary for administrator-supplied article images.

  Files are addressed by their SHA-256 digest, so repeated Telegram uploads are
  idempotent and no user-controlled filename reaches the filesystem. The image
  type is determined from magic bytes rather than Telegram metadata; SVG and
  arbitrary documents are intentionally rejected.

  The public copy lives in `priv/static/images/articles`, which Phoenix already
  exposes below `/images`. A second content-addressed copy lives on the
  configured data volume and is restored into `priv` at boot, so a release
  replacement does not break links already committed in Markdown. Tests can
  pass `:root` to use one isolated directory without the durable mirror.
  """

  @max_bytes 10 * 1_024 * 1_024
  @public_prefix "/images/articles"

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
    if File.regular?(target) do
      case File.read(target) do
        {:ok, ^bytes} -> {:ok, false}
        {:ok, _different} -> {:error, :asset_digest_conflict}
        {:error, reason} -> {:error, {:asset_read_failed, reason}}
      end
    else
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
    end
  end

  defp sha256(bytes) do
    :crypto.hash(:sha256, bytes)
    |> Base.encode16(case: :lower)
  end

  defp static_root, do: Application.app_dir(:ex_blog, "priv/static/images/articles")
  defp durable_root, do: Path.join([ExBlog.Config.get().data_dir, "assets", "images", "articles"])

  defp asset_filename?(filename) do
    Regex.match?(~r/^[a-f0-9]{64}\.(?:jpg|png|gif|webp)$/u, filename)
  end

  defp restore_file!(source, target, filename) do
    bytes = File.read!(Path.join(source, filename))
    expected_digest = Path.rootname(filename)
    expected_extension = filename |> Path.extname() |> String.trim_leading(".")

    case extension(bytes) do
      {:ok, ^expected_extension} ->
        if sha256(bytes) == expected_digest do
          File.write!(Path.join(target, filename), bytes, [:binary])
        else
          raise ArgumentError, "invalid durable article asset: #{filename}"
        end

      _invalid_or_corrupt ->
        raise ArgumentError, "invalid durable article asset: #{filename}"
    end
  end
end
