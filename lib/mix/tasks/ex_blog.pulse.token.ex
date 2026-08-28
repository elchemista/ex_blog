defmodule Mix.Tasks.ExBlog.Pulse.Token do
  @moduledoc """
  Generates the operator credential for the Spectre Studio connection.

      mix ex_blog.pulse.token

  Store the printed value in `EX_BLOG_PULSE_TOKEN` on the blog, and paste the
  same value into Studio's connection form, where it is sealed by Studio's own
  vault key. It travels as the `token` query parameter of the WebSocket URL, so
  it must never be a credential reused anywhere else.

  Rotating it invalidates every stored Studio connection immediately: the
  principal id is derived from the token, so a stale credential cannot silently
  keep a granted scope.
  """

  use Mix.Task

  @shortdoc "Generates the Spectre Pulse connection token"
  @bytes 32

  @impl Mix.Task
  def run([]) do
    token =
      @bytes
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    Mix.shell().info(token)
  end

  def run(_args), do: Mix.raise("usage: mix ex_blog.pulse.token")
end
