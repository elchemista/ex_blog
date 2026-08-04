defmodule ExBlogWeb.Layouts do
  @moduledoc "Application and document layouts for the public blog."

  use ExBlogWeb, :html

  embed_templates "layouts/*"

  def default_description,
    do: gettext("Development notes, technical write-ups and stories from the terminal.")

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
    <a href="#main-content" class="skip-link">{gettext("Skip to content")}</a>
    <div class="site-shell flex min-h-screen flex-col">
      <header
        id="site-header"
        class="sticky top-0 z-40 border-b border-[color:var(--line)] bg-[color:var(--surface-translucent)] backdrop-blur-xl"
      >
        <div class="mx-auto flex h-14 max-w-6xl items-center gap-4 px-4 sm:px-6 lg:px-8">
          <.link
            id="site-brand"
            href={~p"/"}
            class="group flex min-w-0 items-center gap-3"
            aria-label={gettext("ExBlog home")}
          >
            <span class="term-dots" aria-hidden="true">
              <span class="term-dot transition-colors group-hover:bg-[color:var(--fg-dim)]"></span>
              <span class="term-dot"></span>
              <span class="term-dot"></span>
            </span>
            <span class="truncate text-[0.82rem] tracking-tight">
              <span class="t-strong">ex_blog</span><span class="t-dim">@{@current_language}</span><span class="t-dim">:~$</span>
            </span>
            <.cursor class="hidden sm:inline-block" />
          </.link>

          <nav
            id="site-navigation"
            aria-label={gettext("Main navigation")}
            class="ml-auto flex items-center gap-1.5 text-[0.75rem] sm:gap-2.5"
          >
            <.link
              href={~p"/#{@current_language}"}
              class="hidden px-1.5 py-1 t-dim transition hover:t-strong hover:underline hover:decoration-dashed hover:underline-offset-4 sm:block"
            >
              ./{gettext("archive")}
            </.link>
            <.link
              href={~p"/feed.xml"}
              class="hidden px-1.5 py-1 t-dim transition hover:t-strong hover:underline hover:decoration-dashed hover:underline-offset-4 md:block"
            >
              ./feed.xml
            </.link>
            <div id="language-switcher" class="flex items-center gap-1 t-faint">
              <span aria-hidden="true">[</span>
              <span :for={{language, index} <- Enum.with_index(@supported_languages)}>
                <span :if={index > 0} aria-hidden="true" class="px-1">|</span>
                <.link
                  href={~p"/#{language}"}
                  hreflang={language}
                  aria-current={if(language == @current_language, do: "page", else: nil)}
                  class={[
                    "transition",
                    if(language == @current_language,
                      do: "t-strong underline decoration-dashed underline-offset-4",
                      else: "t-dim hover:t-strong"
                    )
                  ]}
                >
                  {language}
                </.link>
              </span>
              <span aria-hidden="true">]</span>
            </div>
            <.theme_toggle />
          </nav>
        </div>
      </header>

      <main id="main-content" tabindex="-1" class="flex-1">
        {render_slot(@inner_block)}
      </main>

      <footer id="site-footer" class="border-t border-[color:var(--line)]">
        <div class="mx-auto flex max-w-6xl flex-col gap-4 px-4 py-8 text-[0.75rem] sm:px-6 lg:px-8">
          <p class="term-prompt t-dim">
            echo "© {@current_year} ExBlog — {gettext("written in Markdown, published from Git")}"
          </p>
          <div class="flex flex-wrap items-center gap-x-5 gap-y-2 t-faint">
            <.link
              href={~p"/#{@current_language}/cookies-policy"}
              class={["transition hover:t-strong"]}
            >
              ./cookies-policy
            </.link>
            <.link
              href={~p"/#{@current_language}/privacy-policy"}
              class={["transition hover:t-strong"]}
            >
              ./privacy+gdpr
            </.link>
            <button
              id="cookie-preferences-button"
              type="button"
              data-cc="show-preferencesModal"
              class={["cursor-pointer transition hover:t-strong"]}
              aria-label={gettext("Open cookie preferences")}
            >
              ./cookie-preferences
            </button>
            <.link href={~p"/sitemap.xml"} class="transition hover:t-strong">./sitemap.xml</.link>
            <.link href={~p"/atom.xml"} class="transition hover:t-strong">./atom.xml</.link>
            <.link href={~p"/feed.xml"} class="transition hover:t-strong">./feed.xml</.link>
            <span class="ml-auto flex items-center gap-2">
              <span class="size-1.5 rounded-full bg-[color:var(--fg-dim)]"></span> exit status 0
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
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed right-4 top-[4.25rem] z-50 flex w-[calc(100vw-2rem)] flex-col gap-3 sm:right-6 sm:w-96"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Connection lost")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Reconnecting")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Retrying in a moment")}
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
      class="flex size-8 items-center justify-center rounded border border-[color:var(--line)] t-dim transition hover:border-[color:var(--line-strong)] hover:t-strong"
      aria-label={gettext("Toggle colour theme")}
      title={gettext("Toggle colour theme")}
    >
      <.icon name="hero-sun" class="size-3.5 dark:hidden" />
      <.icon name="hero-moon" class="hidden size-3.5 dark:block" />
    </button>
    """
  end

  def document_title(nil), do: "ExBlog"
  def document_title("ExBlog"), do: "ExBlog"
  def document_title(title), do: "#{title} · ExBlog"

  def encoded_json_ld(data) do
    data
    |> Jason.encode!(escape: :html_safe)
    |> raw()
  end
end
