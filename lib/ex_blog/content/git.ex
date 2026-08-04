defmodule ExBlog.Content.Git do
  @moduledoc """
  Credential-safe Git boundary for the content checkout.

  The GitHub token is supplied through a short-lived `GIT_ASKPASS` process
  environment. It is never included in a remote URL, command argument, local
  Git configuration, returned error, or log record.
  """

  alias ExBlog.Config
  alias ExBlog.Storage

  @operation_history_limit 500

  @spec ensure_checkout(keyword()) :: {:ok, String.t()} | {:error, term()}
  def ensure_checkout(opts \\ []) do
    path = option(opts, :path, &Config.repository_path/1)

    result =
      cond do
        File.dir?(Path.join(path, ".git")) -> sync(opts)
        File.exists?(path) -> {:error, :checkout_path_is_not_a_git_repository}
        true -> clone(opts)
      end

    record(:ensure_checkout, result, [])
  end

  @spec clone(keyword()) :: {:ok, String.t()} | {:error, term()}
  def clone(opts \\ []) do
    config = Keyword.get(opts, :config, Config.get())
    path = Keyword.get(opts, :path, Config.repository_path(config))
    url = Keyword.get(opts, :url, Config.repository_url(config))
    branch = Keyword.get(opts, :branch, config.github_branch)
    :ok = File.mkdir_p(Path.dirname(path))

    result =
      with_auth(config, fn auth_env ->
        with {:ok, state} <-
               remote_branch_state(url, branch, Path.dirname(path), auth_env, config) do
          clone_remote(state, url, branch, path, auth_env, config)
        end
      end)

    record(:clone, result, [])
  end

  @spec sync(keyword()) :: {:ok, String.t()} | {:error, term()}
  def sync(opts \\ []) do
    config = Keyword.get(opts, :config, Config.get())
    path = Keyword.get(opts, :path, Config.repository_path(config))
    branch = Keyword.get(opts, :branch, config.github_branch)

    result =
      case repository?(path) do
        :ok -> with_auth(config, &sync_authenticated(&1, branch, path, config))
        {:error, _reason} = error -> error
      end

    record(:sync, result, [])
  end

  @spec commit([String.t()], String.t(), keyword()) ::
          {:ok, String.t() | :noop} | {:error, term()}
  def commit(paths, message, opts \\ []) when is_list(paths) and is_binary(message) do
    config = Keyword.get(opts, :config, Config.get())
    checkout = Keyword.get(opts, :path, Config.repository_path(config))

    result =
      with :ok <- repository?(checkout),
           :ok <- safe_relative_paths(paths),
           {:ok, _output} <- command(["add", "--" | paths], checkout, [], config),
           {:ok, changed?} <- staged_changes?(checkout, config) do
        maybe_commit(changed?, message, checkout, config)
      end

    record(:commit, result, paths)
  end

  @spec push(keyword()) :: {:ok, String.t()} | {:error, term()}
  def push(opts \\ []) do
    config = Keyword.get(opts, :config, Config.get())
    path = Keyword.get(opts, :path, Config.repository_path(config))
    branch = Keyword.get(opts, :branch, config.github_branch)

    result =
      case repository?(path) do
        :ok ->
          config
          |> with_auth(&push_authenticated(&1, branch, path, config))
          |> abort_rebase_on_error(path, config)

        {:error, _reason} = error ->
          error
      end

    record(:push, result, [])
  end

  @spec current_commit(keyword()) :: {:ok, String.t()} | {:error, term()}
  def current_commit(opts \\ []) do
    config = Keyword.get(opts, :config, Config.get())
    path = Keyword.get(opts, :path, Config.repository_path(config))

    with :ok <- repository?(path),
         {:ok, output} <- command(["rev-parse", "HEAD"], path, [], config) do
      {:ok, String.trim(output)}
    end
  end

  @spec remote_url(keyword()) :: {:ok, String.t()} | {:error, term()}
  def remote_url(opts \\ []) do
    config = Keyword.get(opts, :config, Config.get())
    path = Keyword.get(opts, :path, Config.repository_path(config))

    with :ok <- repository?(path),
         {:ok, output} <- command(["remote", "get-url", "origin"], path, [], config) do
      {:ok, String.trim(output)}
    end
  end

  defp staged_changes?(path, config) do
    case System.cmd("git", ["diff", "--cached", "--quiet"],
           cd: path,
           env: base_env(),
           stderr_to_stdout: true
         ) do
      {_output, 0} -> {:ok, false}
      {_output, 1} -> {:ok, true}
      {output, status} -> {:error, {:git_failed, status, sanitize(output, config)}}
    end
  end

  defp maybe_commit(false, _message, _path, _config), do: {:ok, :noop}

  defp maybe_commit(true, message, path, config) do
    with {:ok, _output} <- command(["commit", "-m", message], path, author_env(config), config) do
      current_commit(path: path, config: config)
    end
  end

  defp clone_remote(:empty, url, branch, path, auth_env, config) do
    with {:ok, _output} <-
           command(["init", "--initial-branch=#{branch}", path], Path.dirname(path), [], config),
         {:ok, _output} <- command(["remote", "add", "origin", url], path, [], config) do
      initialize_empty_remote(branch, path, auth_env, config)
    end
  end

  defp clone_remote(:present, url, branch, path, auth_env, config) do
    command(
      ["clone", "--branch", branch, "--single-branch", "--", url, path],
      Path.dirname(path),
      auth_env,
      config
    )
    |> normalize_commit(path, config)
  end

  defp sync_remote(:empty, branch, path, auth_env, config) do
    initialize_empty_remote(branch, path, auth_env, config)
  end

  defp sync_remote(:present, branch, path, auth_env, config) do
    with {:ok, _output} <- command(["fetch", "--prune", "origin", branch], path, auth_env, config),
         {:ok, _output} <- command(["reset", "--hard", "origin/#{branch}"], path, [], config) do
      current_commit(path: path, config: config)
    end
  end

  defp sync_authenticated(auth_env, branch, path, config) do
    case remote_branch_state("origin", branch, path, auth_env, config) do
      {:ok, state} -> sync_remote(state, branch, path, auth_env, config)
      {:error, _reason} = error -> error
    end
  end

  defp push_authenticated(auth_env, branch, path, config) do
    with {:ok, state} <- remote_branch_state("origin", branch, path, auth_env, config),
         :ok <- prepare_push(state, branch, path, auth_env, config),
         {:ok, _output} <-
           command(["push", "origin", "HEAD:#{branch}"], path, auth_env, config) do
      current_commit(path: path, config: config)
    end
  end

  defp abort_rebase_on_error({:error, reason}, path, config) do
    _ignored = command(["rebase", "--abort"], path, [], config)
    {:error, reason}
  end

  defp abort_rebase_on_error(result, _path, _config), do: result

  defp prepare_push(:empty, _branch, _path, _auth_env, _config), do: :ok

  defp prepare_push(:present, branch, path, auth_env, config) do
    with {:ok, _output} <- command(["fetch", "origin", branch], path, auth_env, config),
         {:ok, _output} <- rebase(path, branch, config) do
      :ok
    end
  end

  defp remote_branch_state(repository, branch, path, auth_env, config) do
    with {:ok, output} <- command(["ls-remote", "--heads", repository], path, auth_env, config) do
      branches = remote_branches(output)

      cond do
        branches == [] -> {:ok, :empty}
        branch in branches -> {:ok, :present}
        true -> {:error, {:remote_branch_not_found, branch, branches}}
      end
    end
  end

  defp remote_branches(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, ~r/\s+/, parts: 2, trim: true) do
        [_sha, "refs/heads/" <> branch] -> [branch]
        _invalid -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp initialize_empty_remote(branch, path, auth_env, config) do
    with {:ok, _sha} <- ensure_seed_commit(path, config),
         {:ok, _output} <-
           command(
             ["push", "--set-upstream", "origin", "HEAD:#{branch}"],
             path,
             auth_env,
             config
           ) do
      current_commit(path: path, config: config)
    end
  end

  defp ensure_seed_commit(path, config) do
    case current_commit(path: path, config: config) do
      {:ok, sha} ->
        {:ok, sha}

      {:error, _unborn_branch} ->
        with {:ok, files} <- write_seed_files(path, config),
             {:ok, _output} <- command(["add", "--" | files], path, [], config),
             {:ok, _output} <-
               command(
                 ["commit", "-m", "Initialize ExBlog content repository"],
                 path,
                 author_env(config),
                 config
               ) do
          current_commit(path: path, config: config)
        end
    end
  end

  defp write_seed_files(path, config) do
    files =
      [
        {"README.md", seed_readme(config.content_root)},
        {"#{config.content_root}/.gitkeep", ""}
      ] ++
        Enum.map(config.supported_languages, fn language ->
          {"#{config.content_root}/#{language}/.gitkeep", ""}
        end)

    Enum.reduce_while(files, {:ok, []}, fn {relative, contents}, {:ok, written} ->
      destination = Path.join(path, relative)

      with :ok <- File.mkdir_p(Path.dirname(destination)),
           :ok <- File.write(destination, contents) do
        {:cont, {:ok, [relative | written]}}
      else
        {:error, reason} -> {:halt, {:error, {:seed_write_failed, relative, reason}}}
      end
    end)
    |> case do
      {:ok, written} -> {:ok, Enum.reverse(written)}
      {:error, _reason} = error -> error
    end
  end

  defp seed_readme(content_root) do
    """
    # ExBlog content

    This repository is initialized and maintained by ExBlog.
    Articles live under `#{content_root}/<language>/` and follow the Markdown contract documented by the application.
    """
  end

  defp author_env(config) do
    base_env() ++
      [
        {"GIT_AUTHOR_NAME", config.github_author_name},
        {"GIT_AUTHOR_EMAIL", config.github_author_email},
        {"GIT_COMMITTER_NAME", config.github_author_name},
        {"GIT_COMMITTER_EMAIL", config.github_author_email}
      ]
  end

  defp rebase(path, branch, config) do
    case command(["rebase", "origin/#{branch}"], path, [], config) do
      {:ok, output} -> {:ok, output}
      {:error, {:git_failed, _status, output}} -> {:error, {:git_rebase_conflict, output}}
    end
  end

  defp command(args, cd, env, config) do
    case System.cmd("git", args,
           cd: cd,
           env: merge_env(env),
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, sanitize(output, config)}
      {output, status} -> {:error, {:git_failed, status, sanitize(output, config)}}
    end
  rescue
    error -> {:error, {:git_command_failed, Exception.message(error)}}
  end

  defp with_auth(config, fun) do
    unique = System.unique_integer([:positive, :monotonic])
    directory = Path.join(System.tmp_dir!(), "ex-blog-git-askpass-#{unique}")
    script = Path.join(directory, "askpass")
    :ok = File.mkdir(directory)

    :ok =
      File.write(
        script,
        "#!/bin/sh\ncase \"$1\" in\n  *Username*) printf '%s\\n' 'x-access-token' ;;\n  *) printf '%s\\n' \"$EX_BLOG_GIT_TOKEN\" ;;\nesac\n"
      )

    :ok = File.chmod(script, 0o700)

    try do
      fun.([
        {"GIT_ASKPASS", script},
        {"GIT_ASKPASS_REQUIRE", "force"},
        {"GIT_TERMINAL_PROMPT", "0"},
        {"EX_BLOG_GIT_TOKEN", config.github_token}
      ])
    after
      _ignored = File.rm(script)
      _ignored = File.rmdir(directory)
    end
  end

  defp merge_env(env) do
    Map.new(base_env() ++ env)
    |> Map.to_list()
  end

  defp base_env do
    [
      {"GIT_CONFIG_NOSYSTEM", "1"},
      {"GIT_TERMINAL_PROMPT", "0"},
      {"LC_ALL", "C"}
    ]
  end

  defp sanitize(output, config) do
    output
    |> Config.redact(config)
    |> String.slice(0, 8_000)
  end

  defp repository?(path) do
    if File.dir?(Path.join(path, ".git")),
      do: :ok,
      else: {:error, :git_repository_not_found}
  end

  defp safe_relative_paths(paths) do
    if Enum.all?(paths, fn path ->
         Path.type(path) == :relative and
           Enum.all?(Path.split(path), &(&1 not in ["", ".", "..", "/"]))
       end) do
      :ok
    else
      {:error, :unsafe_git_path}
    end
  end

  defp normalize_commit({:ok, _output}, path, config),
    do: current_commit(path: path, config: config)

  defp normalize_commit(error, _path, _config), do: error

  defp option(opts, key, fallback) do
    config = Keyword.get(opts, :config, Config.get())
    Keyword.get(opts, key, fallback.(config))
  end

  defp record(operation, result, files) do
    if Process.whereis(Storage) do
      {ok?, sha, error} = record_values(result)

      entry = %{
        op: to_string(operation),
        commit_sha: sha,
        files: files,
        ok: ok?,
        error: error,
        occurred_at: DateTime.utc_now()
      }

      Storage.update(:git_operations, [], &prepend_operation(&1, entry))
    end

    result
  rescue
    _error -> result
  end

  defp record_values({:ok, sha}) when is_binary(sha), do: {true, sha, nil}
  defp record_values({:ok, _other}), do: {true, nil, nil}

  defp record_values({:error, reason}) do
    error = reason |> inspect(limit: 20, printable_limit: 4_000) |> Config.redact()
    {false, nil, error}
  end

  defp prepend_operation(operations, entry) do
    operations = if is_list(operations), do: operations, else: []
    {:put, Enum.take([entry | operations], @operation_history_limit), :ok}
  end
end
