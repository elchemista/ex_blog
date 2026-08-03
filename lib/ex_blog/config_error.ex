defmodule ExBlog.ConfigError do
  @moduledoc false

  defexception [:message, errors: []]
end
