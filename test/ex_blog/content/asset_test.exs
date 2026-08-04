defmodule ExBlog.Content.AssetTest do
  use ExUnit.Case, async: true

  alias ExBlog.Config
  alias ExBlog.Content.Asset

  test "stores a validated image under a content-addressed public path" do
    root = temporary_directory()
    bytes = <<0xFF, 0xD8, 0xFF, 0xE0, "safe-jpeg">>

    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, first} = Asset.store(bytes, root: root)
    assert first.created?
    assert first.public_path == "/images/articles/#{first.digest}.jpg"
    assert File.read!(Path.join(root, first.filename)) == bytes

    assert {:ok, second} = Asset.store(bytes, root: root)
    refute second.created?
    assert second.public_path == first.public_path
    assert second.digest == first.digest
  end

  test "rejects active or unknown file formats" do
    root = temporary_directory()
    on_exit(fn -> File.rm_rf!(root) end)

    assert {:error, :unsupported_image_format} =
             Asset.store("<svg><script>alert(1)</script></svg>", root: root)

    assert {:error, :empty_image} = Asset.store(<<>>, root: root)
    assert File.ls!(root) == []
  end

  test "restores only content-addressed images from durable storage" do
    source = temporary_directory()
    target = temporary_directory()
    bytes = <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "image">>
    digest = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

    on_exit(fn ->
      File.rm_rf!(source)
      File.rm_rf!(target)
    end)

    File.write!(Path.join(source, "#{digest}.png"), bytes)
    File.write!(Path.join(source, "ignored.txt"), "not an image")

    assert :ok = Asset.restore_static!(source_root: source, root: target)
    assert File.read!(Path.join(target, "#{digest}.png")) == bytes
    refute File.exists?(Path.join(target, "ignored.txt"))
  end

  test "stages a validated Telegram cover in the content repository" do
    root = temporary_directory()
    upload_root = Path.join(root, "uploads")
    config = Config.test_config(data_dir: root)
    bytes = <<"GIF89a", "git-managed-cover">>

    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, stored} = Asset.store(bytes, root: upload_root)

    assert {:ok, [relative_path]} =
             Asset.stage_for_git(stored.public_path,
               config: config,
               source_root: upload_root
             )

    assert relative_path == Path.join(["assets", "images", "articles", stored.filename])

    assert File.read!(Path.join(Config.repository_path(config), relative_path)) == bytes
  end

  test "restores Git-managed covers into durable and public storage" do
    root = temporary_directory()
    repository_assets = Path.join(root, "repository-assets")
    durable = Path.join(root, "durable")
    public = Path.join(root, "public")
    bytes = <<"RIFF", 0, 0, 0, 0, "WEBP", "repository-cover">>
    digest = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    filename = "#{digest}.webp"

    on_exit(fn -> File.rm_rf!(root) end)
    File.mkdir_p!(repository_assets)
    File.write!(Path.join(repository_assets, filename), bytes)

    assert :ok =
             Asset.restore_from_repository(
               config: Config.test_config(data_dir: root),
               repository_root: repository_assets,
               durable_root: durable,
               root: public
             )

    assert File.read!(Path.join(durable, filename)) == bytes
    assert File.read!(Path.join(public, filename)) == bytes
  end

  defp temporary_directory do
    path =
      Path.join(
        System.tmp_dir!(),
        "ex-blog-assets-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end
end
