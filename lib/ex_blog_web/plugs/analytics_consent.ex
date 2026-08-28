defmodule ExBlogWeb.Plugs.AnalyticsConsent do
  @moduledoc """
  Opts a request out of traffic tracking until the reader accepts the analytics
  category.

  Phoenix Analytics is first-party, but it still keeps a session cookie to tell
  one visit from the next, and the ePrivacy Directive asks for prior consent for
  any cookie that is not strictly necessary. The site already asks: the banner
  in `assets/js/app.js` writes the accepted categories into
  `spectre_cookie_consent`, so this plug reads the same cookie rather than
  introducing a second source of truth.

  It runs as a `:before` plug of `PhoenixAnalytics.Plugs.RequestTracker`, where
  `PhoenixAnalytics.Plugs.skip/1` drops the request from the numbers *and*
  stops the tracker from writing its cookies at all — the tracker only opens a
  session once the before plugs have had their say.

  The cookie is written by the browser, so it is parsed defensively: anything
  that is not a consent record naming the analytics category reads as "no
  consent", which is also what a first-time visitor gets.
  """

  @behaviour Plug

  @cookie "spectre_cookie_consent"
  @category "analytics"

  # A consent record is a few hundred bytes; anything larger was not written by
  # the banner and is not worth handing to the JSON parser.
  @max_bytes 4_096

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if consented?(conn), do: conn, else: PhoenixAnalytics.Plugs.skip(conn)
  end

  @doc """
  Returns true when the request carries a consent cookie accepting analytics.
  """
  @spec consented?(Plug.Conn.t()) :: boolean()
  def consented?(conn) do
    conn
    |> Plug.Conn.fetch_cookies()
    |> Map.fetch!(:cookies)
    |> Map.get(@cookie)
    |> accepted?()
  end

  @spec accepted?(term()) :: boolean()
  defp accepted?(value) when is_binary(value) and byte_size(value) <= @max_bytes do
    # The banner stores `encodeURIComponent(JSON.stringify(state))` and Plug
    # hands cookie values over untouched, so the percent-encoding is still here.
    case value |> URI.decode() |> Jason.decode() do
      {:ok, %{"categories" => categories}} when is_list(categories) ->
        @category in categories

      _other ->
        false
    end
  end

  defp accepted?(_value), do: false
end
