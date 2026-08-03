defmodule Mix.Tasks.ExBlog.Admin.HashPasswordTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @task "ex_blog.admin.hash_password"

  test "prints an Argon2 hash that verifies the supplied password" do
    password = "a sufficiently long local password"
    Mix.Task.reenable(@task)

    hash =
      capture_io(fn -> Mix.Task.run(@task, [password]) end)
      |> String.trim()

    assert String.starts_with?(hash, "$argon2id$")
    assert Argon2.verify_pass(password, hash)
  end

  test "rejects short passwords" do
    Mix.Task.reenable(@task)

    assert_raise Mix.Error, ~r/at least 12 characters/, fn ->
      Mix.Task.run(@task, ["too-short"])
    end
  end
end
