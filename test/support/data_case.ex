defmodule ExBlog.DataCase do
  @moduledoc """
  Test case for code that uses ExBlog's durable runtime storage.
  """

  use ExUnit.CaseTemplate

  alias ExBlog.Storage

  using do
    quote do
      import ExBlog.DataCase
    end
  end

  setup _tags do
    :ok = Storage.clear()
    :ok
  end
end
