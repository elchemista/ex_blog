defmodule ExBlogWeb.LocaleLive do
  @moduledoc """
  Restores the Gettext locale inside a LiveView process.

  `ExBlogWeb.Plugs.Locale` only configures the HTTP request process, so every
  `live_session` mounts this hook to apply the same locale to the LiveView.
  """

  import Phoenix.Component, only: [assign: 3]

  alias ExBlogWeb.Plugs.Locale

  def on_mount(:default, params, session, socket) do
    locale =
      Locale.supported(param_locale(params) || session["locale"])

    _previous_locale = Gettext.put_locale(ExBlogWeb.Gettext, locale)

    {:cont, assign(socket, :locale, locale)}
  end

  defp param_locale(%{"lang" => lang}) when is_binary(lang), do: lang
  defp param_locale(_params), do: nil
end
