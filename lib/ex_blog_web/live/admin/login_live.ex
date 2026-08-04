defmodule ExBlogWeb.Admin.LoginLive do
  use ExBlogWeb, :live_view

  alias ExBlog.Config

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    config = Config.get()

    {:ok,
     socket
     |> assign(:page_title, gettext("Administrator area"))
     |> assign(:meta_description, gettext("Restricted access for the ExBlog administrator."))
     |> assign(:robots, "noindex,nofollow,noarchive")
     |> assign(:canonical_url, Config.canonical_url(config) <> "/admin/login")
     |> assign(:current_language, config.default_language)
     |> assign(:supported_languages, config.supported_languages)
     |> assign(:form, to_form(%{"password" => ""}, as: :admin))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_language={@current_language}
      supported_languages={@supported_languages}
    >
      <section
        id="admin-login-page"
        class="mx-auto flex min-h-[calc(100vh-8rem)] max-w-md items-center px-4 py-14 sm:px-6"
      >
        <div class="term-window w-full overflow-hidden">
          <div class="term-bar">
            <span class="term-dots" aria-hidden="true">
              <span class="term-dot"></span>
              <span class="term-dot"></span>
              <span class="term-dot"></span>
            </span>
            <span class="term-title">admin@ex_blog — login</span>
            <span class="ml-auto flex-none t-faint">tty1</span>
          </div>

          <div class="term-body p-5 sm:p-7">
            <p class="term-prompt text-[0.75rem] t-dim">sudo ex_blog admin</p>
            <h1 id="admin-login-heading" class="mt-4 text-xl font-bold tracking-tight t-strong">
              {gettext("Administrator area")}
            </h1>
            <p class="mt-2 text-[0.78rem] leading-6 t-faint">
              <span aria-hidden="true">// </span>{gettext(
                "Enter the configured password to manage the Telegram connection."
              )}
            </p>

            <.form
              for={@form}
              id="admin-login-form"
              action={~p"/admin/login"}
              method="post"
              class="mt-7"
            >
              <.input
                field={@form[:password]}
                type="password"
                label={gettext("password")}
                autocomplete="current-password"
                required
              />

              <.button
                id="admin-login-submit"
                type="submit"
                variant="primary"
                class="term-btn term-btn--primary mt-2 w-full"
              >
                {gettext("Authenticate")} <span aria-hidden="true">→</span>
              </.button>
            </.form>

            <p class="mt-6 border-t border-dashed border-[color:var(--line)] pt-4 text-[0.7rem] leading-5 t-faint">
              <span aria-hidden="true">› </span>{gettext(
                "The password is verified against the Argon2 hash configured on the server."
              )}
            </p>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
