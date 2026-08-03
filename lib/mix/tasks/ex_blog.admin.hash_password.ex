defmodule Mix.Tasks.ExBlog.Admin.HashPassword do
  @moduledoc """
  Generates the Argon2 hash used by the protected administrator area.

      mix ex_blog.admin.hash_password 'a-long-password'

  Store the printed value in `EX_BLOG_ADMIN_PASSWORD_HASH`.
  """

  use Mix.Task

  @shortdoc "Generates the administrator password hash"
  @minimum_length 12

  @impl Mix.Task
  def run([password]) when is_binary(password) do
    validate_password!(password)
    Mix.shell().info(Argon2.hash_pwd_salt(password))
  end

  def run(_args) do
    Mix.raise("usage: mix ex_blog.admin.hash_password 'a-long-password'")
  end

  defp validate_password!(password) do
    cond do
      not String.valid?(password) ->
        Mix.raise("the administrator password must be valid UTF-8")

      String.length(password) < @minimum_length ->
        Mix.raise(
          "the administrator password must contain at least #{@minimum_length} characters"
        )

      true ->
        :ok
    end
  end
end
