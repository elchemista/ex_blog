defmodule ExBlogWeb.Admin.LoginLive do
  use ExBlogWeb, :live_view

  alias ExBlog.Config

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    config = Config.get()

    {:ok,
     socket
     |> assign(:page_title, "Area amministratore")
     |> assign(:meta_description, "Accesso riservato all'amministratore di ExBlog.")
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
        class="relative isolate flex min-h-[calc(100vh-10rem)] items-center justify-center overflow-hidden px-5 py-16 sm:px-8"
      >
        <div class="pointer-events-none absolute inset-0 -z-10" aria-hidden="true">
          <div class="absolute left-1/2 top-16 size-72 -translate-x-1/2 rounded-full bg-amber-300/20 blur-3xl dark:bg-amber-500/10">
          </div>
          <div class="absolute bottom-10 right-[12%] size-52 rounded-full bg-orange-200/25 blur-3xl dark:bg-orange-700/10">
          </div>
        </div>

        <div class="w-full max-w-md">
          <div class="mb-7 text-center">
            <div class="mx-auto mb-5 flex size-14 items-center justify-center rounded-2xl bg-stone-950 text-amber-300 shadow-xl shadow-stone-950/15 dark:bg-amber-400 dark:text-stone-950">
              <.icon name="hero-lock-closed" class="size-7" />
            </div>
            <p class="mb-2 text-xs font-bold uppercase tracking-[0.24em] text-amber-700 dark:text-amber-400">
              Accesso riservato
            </p>
            <h1
              id="admin-login-heading"
              class="font-serif text-4xl font-semibold tracking-tight text-stone-950 dark:text-white"
            >
              Area amministratore
            </h1>
            <p class="mx-auto mt-3 max-w-sm text-sm leading-6 text-stone-600 dark:text-stone-400">
              Inserisci la password configurata per gestire in sicurezza la connessione Telegram.
            </p>
          </div>

          <div class="rounded-[1.75rem] border border-stone-200/90 bg-white/85 p-6 shadow-2xl shadow-stone-900/[0.07] backdrop-blur-xl dark:border-white/10 dark:bg-stone-900/80 dark:shadow-black/25 sm:p-8">
            <.form
              for={@form}
              id="admin-login-form"
              action={~p"/admin/login"}
              method="post"
            >
              <.input
                field={@form[:password]}
                type="password"
                label="Password amministratore"
                autocomplete="current-password"
                required
              />

              <.button
                id="admin-login-submit"
                type="submit"
                variant="primary"
                class="mt-2 inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-xl bg-stone-950 px-5 py-3 text-sm font-bold text-white shadow-lg transition duration-200 hover:-translate-y-0.5 hover:bg-amber-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-600 dark:bg-amber-400 dark:text-stone-950 dark:hover:bg-amber-300"
              >
                Entra nell’area riservata <.icon name="hero-arrow-right" class="size-4" />
              </.button>
            </.form>

            <div class="mt-6 flex items-start gap-3 rounded-xl border border-stone-200 bg-stone-50 px-4 py-3 text-xs leading-5 text-stone-600 dark:border-white/10 dark:bg-white/[0.04] dark:text-stone-400">
              <.icon
                name="hero-shield-check"
                class="mt-0.5 size-4 shrink-0 text-emerald-600 dark:text-emerald-400"
              />
              <p>La password viene verificata contro l’hash Argon2 configurato sul server.</p>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
