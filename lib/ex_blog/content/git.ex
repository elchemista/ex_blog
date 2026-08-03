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
        command(
          ["clone", "--branch", branch, "--single-branch", "--", url, path],
          Path.dirname(path),
          auth_env,
          config
        )
      end)
      |> normalize_commit(path, config)

    record(:clone, result, [])
  end

  @spec sync(keyword()) :: {:ok, String.t()} | {:error, term()}
  def sync(opts \\ []) do
    config = Keyword.get(opts, :config, Config.get())
    path = Keyword.get(opts, :path, Config.repository_path(config))
    branch = Keyword.get(opts, :branch, config.github_branch)

    result =
      with :ok <- repository?(path),
           {:ok, _output} <-
             with_auth(config, fn auth_env ->
               command(["fetch", "--prune", "origin", branch], path, auth_env, config)
             end),
           {:ok, _output} <- command(["reset", "--hard", "origin/#{branch}"], path, [], config) do
        current_commit(path: path, config: config)
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
      with :ok <- repository?(path),
           {:ok, _output} <-
             with_auth(config, fn auth_env ->
               command(["fetch", "origin", branch], path, auth_env, config)
             end),
           {:ok, _output} <- rebase(path, branch, config),
           {:ok, _output} <-
             with_auth(config, fn auth_env ->
               command(["push", "origin", "HEAD:#{branch}"], path, auth_env, config)
             end),
           {:ok, sha} <- current_commit(path: path, config: config) do
        {:ok, sha}
      else
        {:error, reason} ->
          _ignored = command(["rebase", "--abort"], path, [], config)
          {:error, reason}
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
    env =
      base_env() ++
        [
          {"GIT_AUTHOR_NAME", config.github_author_name},
          {"GIT_AUTHOR_EMAIL", config.github_author_email},
          {"GIT_COMMITTER_NAME", config.github_author_name},
          {"GIT_COMMITTER_EMAIL", config.github_author_email}
        ]

    with {:ok, _output} <- command(["commit", "-m", message], path, env, config) do
      current_commit(path: path, config: config)
    end
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
