defmodule ExBlogWeb.Layouts do
  @moduledoc "Application and document layouts for the public blog."

  use ExBlogWeb, :html

  embed_templates "layouts/*"

  @default_description "Idee, appunti e storie pubblicate con cura."

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_language, :string, default: nil
  attr :supported_languages, :list, default: []
  slot :inner_block, required: true

  def app(assigns) do
    languages =
      case assigns.supported_languages do
        [] -> ExBlog.Config.get().supported_languages
        values -> values
      end

    current_language = assigns.current_language || ExBlog.Config.get().default_language

    assigns =
      assigns
      |> assign(:supported_languages, languages)
      |> assign(:current_language, current_language)
      |> assign(:current_year, Date.utc_today().year)

    ~H"""
    <a href="#main-content" class="skip-link">Vai al contenuto</a>
    <div class="site-shell min-h-screen">
      <header
        id="site-header"
        class="sticky top-0 z-40 border-b border-stone-200/80 bg-[color:var(--surface-translucent)] backdrop-blur-xl dark:border-white/10"
      >
        <div class="mx-auto flex h-20 max-w-7xl items-center justify-between gap-5 px-5 sm:px-8 lg:px-12">
          <.link
            id="site-brand"
            href={~p"/"}
            class="group flex items-center gap-3"
            aria-label="ExBlog home"
          >
            <span class="flex size-10 items-center justify-center rounded-xl bg-stone-950 font-serif text-lg font-bold text-amber-400 shadow-lg transition duration-300 group-hover:-rotate-3 group-hover:scale-105 dark:bg-amber-400 dark:text-stone-950">
              E
            </span>
            <span>
              <span class="block font-serif text-xl font-semibold leading-none tracking-tight text-stone-950 dark:text-stone-50">ExBlog</span>
              <span class="mt-1 hidden text-[0.58rem] font-bold uppercase tracking-[0.22em] text-stone-500 sm:block">Pensieri in pubblico</span>
            </span>
          </.link>

          <nav
            id="site-navigation"
            aria-label="Navigazione principale"
            class="flex items-center gap-2 sm:gap-4"
          >
            <.link
              href={~p"/#{@current_language}"}
              class="hidden rounded-full px-3 py-2 text-sm font-semibold text-stone-600 transition hover:bg-stone-100 hover:text-stone-950 dark:text-stone-300 dark:hover:bg-white/[0.06] dark:hover:text-white sm:block"
            >
              Archivio
            </.link>
            <.link
              href={~p"/feed.xml"}
              class="hidden rounded-full px-3 py-2 text-sm font-semibold text-stone-600 transition hover:bg-stone-100 hover:text-stone-950 dark:text-stone-300 dark:hover:bg-white/[0.06] dark:hover:text-white md:block"
            >
              Feed
            </.link>
            <div
              id="language-switcher"
              class="flex items-center rounded-full border border-stone-200 bg-white/60 p-1 dark:border-white/10 dark:bg-white/[0.04]"
            >
              <.link
                :for={language <- @supported_languages}
                href={~p"/#{language}"}
                hreflang={language}
                aria-current={if(language == @current_language, do: "page", else: nil)}
                class={[
                  "rounded-full px-2.5 py-1.5 text-[0.65rem] font-bold uppercase tracking-wider transition",
                  if(language == @current_language,
                    do: "bg-stone-950 text-white shadow-sm dark:bg-amber-400 dark:text-stone-950",
                    else:
                      "text-stone-500 hover:text-stone-950 dark:text-stone-400 dark:hover:text-white"
                  )
                ]}
              >
                {language}
              </.link>
            </div>
            <.theme_toggle />
          </nav>
        </div>
      </header>

      <main id="main-content" tabindex="-1">
        {render_slot(@inner_block)}
      </main>

      <footer id="site-footer" class="border-t border-stone-200/80 dark:border-white/10">
        <div class="mx-auto flex max-w-7xl flex-col gap-5 px-5 py-10 text-sm text-stone-500 sm:flex-row sm:items-center sm:justify-between sm:px-8 lg:px-12">
          <p>© {@current_year} ExBlog. Scritto con attenzione, pubblicato da Git.</p>
          <div class="flex items-center gap-5 font-semibold">
            <.link
              href={~p"/sitemap.xml"}
              class="transition hover:text-amber-700 dark:hover:text-amber-400"
            >Sitemap</.link>
            <.link
              href={~p"/atom.xml"}
              class="transition hover:text-amber-700 dark:hover:text-amber-400"
            >Atom</.link>
            <span class="flex items-center gap-2 text-stone-400">
              <span class="size-1.5 rounded-full bg-emerald-500 shadow-[0_0_0_3px_rgba(16,185,129,0.12)]"></span>
              Online
            </span>
          </div>
        </div>
      </footer>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Connessione interrotta")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Riconnessione in corso")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Qualcosa non ha funzionato")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Riprovo tra un istante")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <button
      id="theme-toggle"
      type="button"
      data-theme-toggle
      class="group flex size-9 items-center justify-center rounded-full border border-stone-200 bg-white/60 text-stone-600 transition duration-300 hover:-rotate-6 hover:border-amber-300 hover:text-amber-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-600 dark:border-white/10 dark:bg-white/[0.04] dark:text-stone-300 dark:hover:text-amber-300"
      aria-label="Cambia tema colore"
      title="Cambia tema colore"
    >
      <.icon name="hero-sun" class="size-4 dark:hidden" />
      <.icon name="hero-moon" class="hidden size-4 dark:block" />
    </button>
    """
  end

  def document_title(nil), do: "ExBlog"
  def document_title("ExBlog"), do: "ExBlog"
  def document_title(title), do: "#{title} · ExBlog"
  def default_description, do: @default_description

  def encoded_json_ld(data) do
    data
    |> Jason.encode!(escape: :html_safe)
    |> raw()
  end
end
