defmodule ExBlog.Content.WriterTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Config
  alias ExBlog.Content
  alias ExBlog.Content.Git
  alias ExBlog.Content.Index
  alias ExBlog.Content.Writer

  setup do
    root = temporary_directory()
    origin = Path.join(root, "origin.git")
    seed = Path.join(root, "seed")

    git!(["init", "--bare", origin], root)
    File.mkdir_p!(seed)
    git!(["init", "--initial-branch=main"], seed)
    File.mkdir_p!(Path.join(seed, "content/it"))
    File.write!(Path.join(seed, "content/it/.gitkeep"), "")
    git!(["add", "."], seed)
    git!(["commit", "-m", "Seed"], seed, author_env())
    git!(["remote", "add", "origin", origin], seed)
    git!(["push", "-u", "origin", "main"], seed)

    config =
      Config.test_config(
        data_dir: root,
        github_branch: "main",
        github_token: "writer-test-token"
      )

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

    on_exit(fn -> File.rm_rf!(root) end)

    %{config: config, origin: origin}
  end

  test "creates, publishes, and deletes a canonical article using the elchemista slugifier", %{
    config: config,
    origin: origin
  } do
    assert Slug.slugify("L’arte dell’Elixir: già pronta!") ==
             "larte-dellelixir-gia-pronta"

    assert {:ok, draft} =
             Writer.create(
               %{
                 title: "L’arte dell’Elixir: già pronta!",
                 lang: "it",
                 date: "2026-08-03",
                 body: "## Corpo\n\nUn testo completo.",
                 tags: ["elixir", "scrittura"]
               },
               config: config
             )

    assert draft.slug == "larte-dellelixir-gia-pronta"
    assert draft.status == :draft
    assert draft.path == "content/it/2026-08-03-larte-dellelixir-gia-pronta.md"

    absolute = Path.join(Config.repository_path(config), draft.path)
    source = File.read!(absolute)
    assert source =~ ~s(slug: "larte-dellelixir-gia-pronta")
    assert source =~ "status: draft"

    {remote_source, 0} =
      System.cmd("git", ["--git-dir", origin, "show", "main:#{draft.path}"],
        stderr_to_stdout: true
      )

    assert remote_source == source

    assert {:ok, published} = Writer.publish(draft, config: config)
    assert published.status == :published
    assert {:ok, ^published} = Content.get("it", published.slug)

    assert {:error, :seo_title_too_long} =
             Writer.update(published, %{seo_title: String.duplicate("x", 61)}, config: config)

    assert :ok = Writer.delete(published, config: config)
    assert {:error, :not_found} = Content.get("it", published.slug, published_only?: false)

    {_output, 128} =
      System.cmd("git", ["--git-dir", origin, "show", "main:#{draft.path}"],
        stderr_to_stdout: true
      )
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
        "ex-blog-writer-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end
end
