defmodule ExBlog.Content.GitTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Config
  alias ExBlog.Content.Git

  setup do
    root = temporary_directory()
    origin = Path.join(root, "origin.git")
    seed = Path.join(root, "seed")
    checkout = Path.join(root, "checkout")

    git!(["init", "--bare", origin], root)
    File.mkdir_p!(seed)
    git!(["init", "--initial-branch=main"], seed)
    File.mkdir_p!(Path.join(seed, "content/it"))
    File.write!(Path.join(seed, "content/it/README.md"), "seed\n")
    git!(["add", "."], seed)
    git!(["commit", "-m", "Seed"], seed, author_env())
    git!(["remote", "add", "origin", origin], seed)
    git!(["push", "-u", "origin", "main"], seed)

    on_exit(fn -> File.rm_rf!(root) end)

    config =
      Config.test_config(
        data_dir: root,
        github_token: "github-token-that-must-not-leak",
        github_branch: "main"
      )

    %{config: config, origin: origin, checkout: checkout, root: root}
  end

  test "clone, commit, and push keep credentials out of the repository", context do
    assert {:ok, first_sha} =
             Git.clone(
               config: context.config,
               path: context.checkout,
               url: context.origin,
               branch: "main"
             )

    assert String.length(first_sha) == 40
    assert {:ok, remote} = Git.remote_url(config: context.config, path: context.checkout)
    assert remote == context.origin

    git_config = File.read!(Path.join(context.checkout, ".git/config"))
    refute git_config =~ context.config.github_token

    relative = "content/it/2026-08-03-new.md"
    File.write!(Path.join(context.checkout, relative), "new article\n")

    assert {:ok, commit_sha} =
             Git.commit([relative], "Add article", config: context.config, path: context.checkout)

    assert commit_sha != first_sha

    assert {:ok, ^commit_sha} =
             Git.push(config: context.config, path: context.checkout, branch: "main")

    {body, 0} =
      System.cmd("git", ["--git-dir", context.origin, "show", "main:#{relative}"],
        stderr_to_stdout: true
      )

    assert body == "new article\n"
  end

  test "rejects paths that could escape the checkout", context do
    assert {:ok, _sha} =
             Git.clone(
               config: context.config,
               path: context.checkout,
               url: context.origin,
               branch: "main"
             )

    assert {:error, :unsafe_git_path} =
             Git.commit(["../outside"], "Unsafe",
               config: context.config,
               path: context.checkout
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
        "ex-blog-git-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end
end
