defmodule ExBlog.Content.SyncTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Config
  alias ExBlog.Content
  alias ExBlog.Content.Git
  alias ExBlog.Content.Index
  alias ExBlog.Content.Sync

  setup do
    root = temporary_directory()
    origin = Path.join(root, "origin.git")
    publisher = Path.join(root, "publisher")
    previous_config = Config.get()

    git!(["init", "--bare", origin], root)
    File.mkdir_p!(publisher)
    git!(["init", "--initial-branch=main"], publisher)
    File.mkdir_p!(Path.join(publisher, "content/en"))
    File.write!(Path.join(publisher, "content/en/.gitkeep"), "")
    git!(["add", "."], publisher)
    git!(["commit", "-m", "Seed"], publisher, author_env())
    git!(["remote", "add", "origin", origin], publisher)
    git!(["push", "-u", "origin", "main"], publisher)

    config =
      Config.test_config(
        data_dir: root,
        github_branch: "main",
        github_token: "sync-test-token",
        git_sync_interval_ms: 60_000
      )

    :ok = Config.install(config)
    public_assets = Path.join(root, "public-assets")
    durable_assets = Path.join(root, "durable-assets")

    assert {:ok, _commit} =
             Git.clone(
               config: config,
               path: Config.repository_path(config),
               url: origin,
               branch: "main"
             )

    start_supervised!(
      {Index, root: Config.repository_path(config), content_root: config.content_root}
    )

    start_supervised!({Sync, root: public_assets, durable_root: durable_assets})

    on_exit(fn ->
      :ok = Config.install(previous_config)
      File.rm_rf!(root)
    end)

    %{publisher: publisher, public_assets: public_assets, durable_assets: durable_assets}
  end

  test "pulls new GitHub content and rebuilds draft and published visibility", %{
    publisher: publisher,
    public_assets: public_assets,
    durable_assets: durable_assets
  } do
    cover_bytes = <<0xFF, 0xD8, 0xFF, 0xE0, "cover-pulled-from-git">>
    cover_digest = :crypto.hash(:sha256, cover_bytes) |> Base.encode16(case: :lower)
    cover_filename = "#{cover_digest}.jpg"
    cover_path = "/images/articles/#{cover_filename}"
    repository_cover = Path.join([publisher, "assets", "images", "articles", cover_filename])
    File.mkdir_p!(Path.dirname(repository_cover))
    File.write!(repository_cover, cover_bytes)

    path = Path.join(publisher, "content/en/2026-08-04-synchronized.md")
    File.write!(path, article("draft", cover_path))
    git!(["add", "."], publisher)
    git!(["commit", "-m", "Create synchronized draft"], publisher, author_env())
    git!(["push", "origin", "main"], publisher)

    assert {:ok, %{total: 1, invalid: 0, commit: draft_commit}} = Sync.sync_now()
    assert {:ok, draft} = Content.get("en", "synchronized", published_only?: false)
    assert draft.status == :draft
    assert draft.cover == cover_path
    assert {:error, :not_found} = Content.get("en", "synchronized")
    assert File.read!(Path.join(public_assets, cover_filename)) == cover_bytes
    assert File.read!(Path.join(durable_assets, cover_filename)) == cover_bytes

    File.write!(path, article("published", cover_path))
    git!(["add", "."], publisher)
    git!(["commit", "-m", "Publish synchronized article"], publisher, author_env())
    git!(["push", "origin", "main"], publisher)

    assert {:ok, %{total: 1, invalid: 0, commit: published_commit}} = Sync.sync_now()
    assert published_commit != draft_commit
    assert {:ok, published} = Content.get("en", "synchronized")
    assert published.status == :published
  end

  defp article(status, cover) do
    """
    ---
    title: Synchronized
    slug: synchronized
    lang: en
    status: #{status}
    date: 2026-08-04
    cover: #{Jason.encode!(cover)}
    tags: []
    ---
    Content pulled from the canonical Git repository.
    """
  end

  defp git!(args, directory, env \\ []) do
    case System.cmd("git", args, cd: directory, env: env, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> flunk("git exited with #{status}: #{output}")
    end
  end

  defp author_env do
    [
      {"GIT_AUTHOR_NAME", "ExBlog Test"},
      {"GIT_AUTHOR_EMAIL", "test@example.com"},
      {"GIT_COMMITTER_NAME", "ExBlog Test"},
      {"GIT_COMMITTER_EMAIL", "test@example.com"}
    ]
  end

  defp temporary_directory do
    path =
      Path.join(
        System.tmp_dir!(),
        "ex-blog-sync-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end
end
