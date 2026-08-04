defmodule ExBlogWeb.Plugs.Locale do
  @moduledoc """
  Puts the Gettext locale for the current request.

  ExBlog already carries the language in the path (`/:lang/...`), so this plug
  never redirects: it only reads the first path segment, validates it against
  the configured `supported_languages` and falls back to the configured default
  language. The resolved value is stored in the session so LiveViews mounted
  from the same connection can restore it.
  """

  @behaviour Plug

  import Plug.Conn

  alias ExBlog.Config

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{halted: true} = conn, _opts), do: conn

  def call(conn, _opts) do
    locale = resolve(conn)

    _previous_locale = Gettext.put_locale(ExBlogWeb.Gettext, locale)

    conn
    |> assign(:locale, locale)
    |> put_session(:locale, locale)
  end

  @doc "Returns the locale for a connection without touching the process."
  @spec resolve(Plug.Conn.t()) :: String.t()
  def resolve(conn) do
    config = Config.get()

    path_locale(conn.path_info, config.supported_languages) ||
      session_locale(conn, config.supported_languages) ||
      config.default_language
  end

  @doc "Returns a supported locale or the configured default."
  @spec supported(term()) :: String.t()
  def supported(locale) do
    config = Config.get()

    if is_binary(locale) and locale in config.supported_languages,
      do: locale,
      else: config.default_language
  end

  defp path_locale([segment | _rest], supported) when is_binary(segment) do
    if segment in supported, do: segment
  end

  defp path_locale(_path_info, _supported), do: nil

  defp session_locale(conn, supported) do
    case get_session(conn, :locale) do
      locale when is_binary(locale) -> if locale in supported, do: locale
      _missing -> nil
    end
  end
end
