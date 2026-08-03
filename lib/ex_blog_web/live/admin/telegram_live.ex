defmodule ExBlogWeb.Admin.TelegramLive do
  use ExBlogWeb, :live_view

  alias ExBlog.Config
  alias ExBlog.Telegram.{QR, Transport}

  @default_snapshot %{
    auth_state: :unavailable,
    connection_status: :disconnected,
    last_error?: false,
    password_hint: nil,
    qr_link: nil,
    session_id: "unavailable"
  }

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    config = Config.get()

    if connected?(socket) do
      :ok = Transport.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, "Connessione Telegram")
     |> assign(:meta_description, "Gestione riservata della sessione Telegram di ExBlog.")
     |> assign(:robots, "noindex,nofollow,noarchive")
     |> assign(:canonical_url, Config.canonical_url(config) <> "/admin/telegram")
     |> assign(:current_language, config.default_language)
     |> assign(:supported_languages, config.supported_languages)
     |> assign(:phone_form, empty_form(:telegram_phone, "phone"))
     |> assign(:code_form, empty_form(:telegram_code, "code"))
     |> assign(:password_form, empty_form(:telegram_password, "password"))
     |> assign_snapshot(fetch_snapshot())}
  end

  @impl Phoenix.LiveView
  def handle_event("refresh", _params, socket) do
    {:noreply, assign_snapshot(socket, fetch_snapshot())}
  end

  def handle_event("connect", _params, socket) do
    run_action(socket, &Transport.connect/0, "Riconnessione Telegram avviata.")
  end

  def handle_event("request_qr", _params, socket) do
    run_action(socket, &Transport.request_qr/0, "QR richiesto a Telegram.")
  end

  def handle_event("provide_phone", %{"telegram_phone" => params}, socket) do
    phone = params |> Map.get("phone", "") |> normalize_phone()

    if valid_phone?(phone) do
      socket = assign(socket, :phone_form, empty_form(:telegram_phone, "phone"))
      run_action(socket, fn -> Transport.provide_phone_number(phone) end, "Numero inviato.")
    else
      {:noreply,
       socket
       |> assign(:phone_form, empty_form(:telegram_phone, "phone"))
       |> put_flash(
         :error,
         "Inserisci un numero internazionale valido, ad esempio +393331234567."
       )}
    end
  end

  def handle_event("provide_code", %{"telegram_code" => params}, socket) do
    code = params |> Map.get("code", "") |> normalize_code()

    if Regex.match?(~r/^\d{3,10}$/, code) do
      socket = assign(socket, :code_form, empty_form(:telegram_code, "code"))
      run_action(socket, fn -> Transport.provide_auth_code(code) end, "Codice inviato.")
    else
      {:noreply,
       socket
       |> assign(:code_form, empty_form(:telegram_code, "code"))
       |> put_flash(:error, "Inserisci il codice numerico ricevuto da Telegram.")}
    end
  end

  def handle_event("provide_password", %{"telegram_password" => params}, socket) do
    password = Map.get(params, "password", "")

    if valid_telegram_password?(password) do
      socket = assign(socket, :password_form, empty_form(:telegram_password, "password"))

      run_action(
        socket,
        fn -> Transport.provide_password(password) end,
        "Password di verifica inviata."
      )
    else
      {:noreply,
       socket
       |> assign(:password_form, empty_form(:telegram_password, "password"))
       |> put_flash(:error, "Inserisci la password di verifica in due passaggi.")}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:telegram_connection_updated, snapshot}, socket) when is_map(snapshot) do
    {:noreply, assign_snapshot(socket, snapshot)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

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
        id="admin-telegram-page"
        class="mx-auto min-h-[calc(100vh-10rem)] max-w-7xl px-5 py-10 sm:px-8 lg:px-12 lg:py-14"
      >
        <header class="mb-8 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p class="mb-2 flex items-center gap-2 text-xs font-bold uppercase tracking-[0.22em] text-amber-700 dark:text-amber-400">
              <span class="size-1.5 rounded-full bg-amber-500"></span> Area riservata
            </p>
            <h1
              id="admin-telegram-heading"
              class="font-serif text-4xl font-semibold tracking-tight text-stone-950 dark:text-white sm:text-5xl"
            >
              Connessione Telegram
            </h1>
            <p class="mt-3 max-w-2xl text-sm leading-6 text-stone-600 dark:text-stone-400">
              Collega l’account che controlla ExBlog e segui in tempo reale ogni passaggio dell’autenticazione TDLib.
            </p>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <button
              id="telegram-refresh-button"
              type="button"
              phx-click="refresh"
              class="inline-flex min-h-10 items-center gap-2 rounded-xl border border-stone-300 bg-white px-4 py-2 text-sm font-bold text-stone-700 shadow-sm transition hover:-translate-y-0.5 hover:border-amber-400 hover:text-amber-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-600 dark:border-white/15 dark:bg-white/[0.05] dark:text-stone-200 dark:hover:text-amber-300"
            >
              <.icon name="hero-arrow-path" class="size-4 phx-click-loading:animate-spin" /> Aggiorna
            </button>
            <.link
              id="admin-logout-link"
              href={~p"/admin/logout"}
              method="delete"
              class="inline-flex min-h-10 items-center gap-2 rounded-xl px-4 py-2 text-sm font-bold text-stone-500 transition hover:bg-stone-200/70 hover:text-stone-950 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-600 dark:text-stone-400 dark:hover:bg-white/[0.06] dark:hover:text-white"
            >
              <.icon name="hero-arrow-left-on-rectangle" class="size-4" /> Esci
            </.link>
          </div>
        </header>

        <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
          <main class="order-2 lg:order-1">
            <div class="overflow-hidden rounded-[2rem] border border-stone-200/90 bg-white/85 shadow-2xl shadow-stone-900/[0.06] backdrop-blur-xl dark:border-white/10 dark:bg-stone-900/80 dark:shadow-black/20">
              <div class="border-b border-stone-200/80 px-6 py-5 dark:border-white/10 sm:px-8">
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <h2 class="font-serif text-2xl font-semibold text-stone-950 dark:text-white">
                      Associazione account
                    </h2>
                    <p class="mt-1 text-sm text-stone-500 dark:text-stone-400">
                      {auth_state_description(@telegram.auth_state)}
                    </p>
                  </div>
                  <span
                    id="telegram-connection-status"
                    role="status"
                    aria-live="polite"
                    class={[
                      "inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-xs font-bold",
                      status_classes(@telegram.connection_status)
                    ]}
                  >
                    <span class={[
                      "size-2 rounded-full",
                      status_dot_classes(@telegram.connection_status)
                    ]}></span>
                    {status_label(@telegram.connection_status)}
                  </span>
                </div>
              </div>

              <div class="p-6 sm:p-8">
                <div
                  :if={@telegram.last_error?}
                  id="telegram-connection-error"
                  role="alert"
                  class="mb-6 flex items-start gap-3 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-900 dark:border-red-900/70 dark:bg-red-950/40 dark:text-red-100"
                >
                  <.icon name="hero-exclamation-triangle" class="mt-0.5 size-5 shrink-0" />
                  <p>
                    Telegram ha segnalato un problema. Puoi aggiornare lo stato o riprovare la connessione.
                  </p>
                </div>

                <div
                  :if={@telegram.connection_status == :connected}
                  id="telegram-connected-panel"
                  class="py-8 text-center"
                >
                  <div class="mx-auto flex size-20 items-center justify-center rounded-full bg-emerald-100 text-emerald-700 ring-8 ring-emerald-50 dark:bg-emerald-500/15 dark:text-emerald-300 dark:ring-emerald-500/[0.06]">
                    <.icon name="hero-check" class="size-10" />
                  </div>
                  <h2 class="mt-7 font-serif text-3xl font-semibold text-stone-950 dark:text-white">
                    Telegram è collegato
                  </h2>
                  <p class="mx-auto mt-3 max-w-lg text-sm leading-6 text-stone-600 dark:text-stone-400">
                    La sessione TDLib è autorizzata e pronta a ricevere i messaggi dell’amministratore configurato.
                  </p>
                </div>

                <div
                  :if={@telegram.auth_state == :wait_phone_number}
                  id="telegram-pairing-options"
                  class="grid gap-5 md:grid-cols-2"
                >
                  <article class="flex flex-col rounded-2xl border border-amber-200 bg-amber-50/70 p-5 dark:border-amber-500/20 dark:bg-amber-500/[0.06]">
                    <div class="mb-4 flex size-11 items-center justify-center rounded-xl bg-amber-500 text-stone-950 shadow-sm">
                      <.icon name="hero-qr-code" class="size-6" />
                    </div>
                    <h3 class="font-serif text-xl font-semibold text-stone-950 dark:text-white">
                      Collega con QR
                    </h3>
                    <p class="mt-2 flex-1 text-sm leading-6 text-stone-600 dark:text-stone-400">
                      Metodo consigliato: apri Telegram su un dispositivo già autenticato e scansiona il codice.
                    </p>
                    <button
                      id="telegram-request-qr-button"
                      type="button"
                      phx-click="request_qr"
                      phx-disable-with="Richiesta in corso…"
                      class="mt-5 inline-flex min-h-11 items-center justify-center gap-2 rounded-xl bg-stone-950 px-4 py-2.5 text-sm font-bold text-white shadow-md transition hover:-translate-y-0.5 hover:bg-amber-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-600 disabled:opacity-60 dark:bg-amber-400 dark:text-stone-950 dark:hover:bg-amber-300"
                    >
                      <.icon name="hero-qr-code" class="size-4" /> Genera il QR
                    </button>
                  </article>

                  <article class="rounded-2xl border border-stone-200 bg-stone-50/70 p-5 dark:border-white/10 dark:bg-white/[0.03]">
                    <div class="mb-4 flex size-11 items-center justify-center rounded-xl bg-stone-200 text-stone-700 dark:bg-white/10 dark:text-stone-200">
                      <.icon name="hero-device-phone-mobile" class="size-6" />
                    </div>
                    <h3 class="font-serif text-xl font-semibold text-stone-950 dark:text-white">
                      Usa il numero
                    </h3>
                    <p class="mt-2 text-sm leading-6 text-stone-600 dark:text-stone-400">
                      In alternativa inserisci il numero internazionale associato all’account.
                    </p>
                    <.form
                      for={@phone_form}
                      id="telegram-phone-form"
                      phx-submit="provide_phone"
                      class="mt-4"
                    >
                      <.input
                        field={@phone_form[:phone]}
                        type="tel"
                        label="Numero di telefono"
                        placeholder="+393331234567"
                        autocomplete="tel"
                        required
                      />
                      <.button
                        id="telegram-phone-submit"
                        type="submit"
                        class={submit_button_classes()}
                      >
                        Continua con il numero
                      </.button>
                    </.form>
                  </article>
                </div>

                <div
                  :if={@telegram.auth_state == :requesting_qr}
                  id="telegram-qr-loading"
                  class="py-12 text-center"
                  role="status"
                >
                  <.icon
                    name="hero-arrow-path"
                    class="mx-auto size-10 animate-spin text-amber-600 dark:text-amber-400"
                  />
                  <h2 class="mt-5 font-serif text-2xl font-semibold text-stone-950 dark:text-white">
                    Generazione del QR
                  </h2>
                  <p class="mt-2 text-sm text-stone-500 dark:text-stone-400">
                    Attendo il link temporaneo da Telegram…
                  </p>
                </div>

                <div
                  :if={@telegram.auth_state == :wait_other_device_confirmation}
                  id="telegram-qr-panel"
                  class="grid items-center gap-8 md:grid-cols-[minmax(0,20rem)_1fr]"
                >
                  <div class="mx-auto w-full max-w-xs">
                    <div
                      :if={@qr_svg}
                      id="telegram-qr-code"
                      role="img"
                      aria-label="Codice QR per collegare Telegram"
                      class="aspect-square overflow-hidden rounded-3xl border border-stone-200 bg-white p-4 shadow-xl shadow-stone-900/10 [&_svg]:block [&_svg]:size-full"
                    >
                      {raw(@qr_svg)}
                    </div>
                    <div
                      :if={!@qr_svg}
                      id="telegram-qr-unavailable"
                      class="flex aspect-square items-center justify-center rounded-3xl border border-dashed border-red-300 bg-red-50 p-6 text-center text-sm text-red-800 dark:border-red-800 dark:bg-red-950/30 dark:text-red-200"
                    >
                      Non è stato possibile renderizzare il QR. Richiedine uno nuovo.
                    </div>
                  </div>

                  <div>
                    <p class="text-xs font-bold uppercase tracking-[0.2em] text-amber-700 dark:text-amber-400">
                      QR temporaneo
                    </p>
                    <h2 class="mt-2 font-serif text-3xl font-semibold text-stone-950 dark:text-white">
                      Scansiona con Telegram
                    </h2>
                    <ol class="mt-5 space-y-4 text-sm leading-6 text-stone-600 dark:text-stone-300">
                      <li class="flex gap-3">
                        <span
                          aria-hidden="true"
                          class="flex size-7 shrink-0 items-center justify-center rounded-full bg-stone-950 text-xs font-bold text-white dark:bg-amber-400 dark:text-stone-950"
                        >1</span>
                        Apri Telegram sul telefono già autenticato.
                      </li>
                      <li class="flex gap-3">
                        <span
                          aria-hidden="true"
                          class="flex size-7 shrink-0 items-center justify-center rounded-full bg-stone-950 text-xs font-bold text-white dark:bg-amber-400 dark:text-stone-950"
                        >2</span>
                        Vai in Impostazioni, Dispositivi, Collega dispositivo desktop.
                      </li>
                      <li class="flex gap-3">
                        <span
                          aria-hidden="true"
                          class="flex size-7 shrink-0 items-center justify-center rounded-full bg-stone-950 text-xs font-bold text-white dark:bg-amber-400 dark:text-stone-950"
                        >3</span>
                        Inquadra il codice e attendi la conferma su questa pagina.
                      </li>
                    </ol>
                    <button
                      id="telegram-renew-qr-button"
                      type="button"
                      phx-click="request_qr"
                      class="mt-6 inline-flex min-h-10 items-center gap-2 rounded-xl border border-stone-300 bg-white px-4 py-2 text-sm font-bold text-stone-700 transition hover:border-amber-400 hover:text-amber-800 dark:border-white/15 dark:bg-white/[0.05] dark:text-stone-200 dark:hover:text-amber-300"
                    >
                      <.icon name="hero-arrow-path" class="size-4" /> Genera un nuovo QR
                    </button>
                  </div>
                </div>

                <div
                  :if={@telegram.auth_state in [:wait_code, :submitting_phone, :submitting_code]}
                  id="telegram-code-panel"
                  class="mx-auto max-w-md py-6"
                >
                  <div class="mb-5 flex size-12 items-center justify-center rounded-2xl bg-sky-100 text-sky-700 dark:bg-sky-500/15 dark:text-sky-300">
                    <.icon name="hero-chat-bubble-left-right" class="size-6" />
                  </div>
                  <h2 class="font-serif text-3xl font-semibold text-stone-950 dark:text-white">
                    Inserisci il codice
                  </h2>
                  <p class="mt-2 text-sm leading-6 text-stone-600 dark:text-stone-400">
                    Telegram ha inviato un codice all’account. Non verrà memorizzato da ExBlog.
                  </p>
                  <.form
                    for={@code_form}
                    id="telegram-code-form"
                    phx-submit="provide_code"
                    class="mt-6"
                  >
                    <.input
                      field={@code_form[:code]}
                      type="text"
                      label="Codice Telegram"
                      autocomplete="one-time-code"
                      pattern="[0-9]{3,10}"
                      required
                    />
                    <.button
                      id="telegram-code-submit"
                      type="submit"
                      class={submit_button_classes()}
                    >
                      Verifica codice
                    </.button>
                  </.form>
                </div>

                <div
                  :if={@telegram.auth_state in [:wait_password, :submitting_password]}
                  id="telegram-password-panel"
                  class="mx-auto max-w-md py-6"
                >
                  <div class="mb-5 flex size-12 items-center justify-center rounded-2xl bg-violet-100 text-violet-700 dark:bg-violet-500/15 dark:text-violet-300">
                    <.icon name="hero-key" class="size-6" />
                  </div>
                  <h2 class="font-serif text-3xl font-semibold text-stone-950 dark:text-white">
                    Verifica in due passaggi
                  </h2>
                  <p class="mt-2 text-sm leading-6 text-stone-600 dark:text-stone-400">
                    Inserisci la password Telegram 2FA. Viene inoltrata direttamente a TDLib e non viene salvata.
                  </p>
                  <p
                    :if={@telegram.password_hint}
                    id="telegram-password-hint"
                    class="mt-3 rounded-xl bg-stone-100 px-3 py-2 text-sm text-stone-600 dark:bg-white/[0.05] dark:text-stone-300"
                  >
                    Suggerimento: {@telegram.password_hint}
                  </p>
                  <.form
                    for={@password_form}
                    id="telegram-password-form"
                    phx-submit="provide_password"
                    class="mt-6"
                  >
                    <.input
                      field={@password_form[:password]}
                      type="password"
                      label="Password Telegram"
                      autocomplete="current-password"
                      required
                    />
                    <.button
                      id="telegram-password-submit"
                      type="submit"
                      class={submit_button_classes()}
                    >
                      Completa la verifica
                    </.button>
                  </.form>
                </div>

                <div
                  :if={@telegram.auth_state in [:starting, :connecting, :unavailable, :disconnected]}
                  id="telegram-disconnected-panel"
                  class="py-10 text-center"
                >
                  <div class="mx-auto flex size-16 items-center justify-center rounded-2xl bg-stone-100 text-stone-500 dark:bg-white/[0.06] dark:text-stone-300">
                    <.icon name="hero-signal-slash" class="size-8" />
                  </div>
                  <h2 class="mt-5 font-serif text-2xl font-semibold text-stone-950 dark:text-white">
                    Connessione non pronta
                  </h2>
                  <p class="mx-auto mt-2 max-w-md text-sm leading-6 text-stone-600 dark:text-stone-400">
                    Avvia o riprova la sessione TDLib per ricevere il prossimo stato di autenticazione.
                  </p>
                  <button
                    id="telegram-connect-button"
                    type="button"
                    phx-click="connect"
                    phx-disable-with="Connessione…"
                    class="mt-6 inline-flex min-h-11 items-center justify-center gap-2 rounded-xl bg-stone-950 px-5 py-2.5 text-sm font-bold text-white shadow-md transition hover:-translate-y-0.5 hover:bg-amber-700 dark:bg-amber-400 dark:text-stone-950 dark:hover:bg-amber-300"
                  >
                    <.icon name="hero-signal" class="size-4" /> Connetti Telegram
                  </button>
                </div>
              </div>
            </div>
          </main>

          <aside class="order-1 space-y-4 lg:order-2" aria-label="Dettagli connessione">
            <div class="rounded-2xl border border-stone-200/90 bg-white/75 p-5 shadow-lg shadow-stone-900/[0.04] backdrop-blur dark:border-white/10 dark:bg-stone-900/70">
              <div class="flex items-center gap-3">
                <div class="flex size-10 items-center justify-center rounded-xl bg-sky-100 text-sky-700 dark:bg-sky-500/15 dark:text-sky-300">
                  <.icon name="hero-paper-airplane" class="size-5" />
                </div>
                <div>
                  <h2 class="text-sm font-bold text-stone-950 dark:text-white">Sessione TDLib</h2>
                  <p
                    id="telegram-session-id"
                    class="mt-0.5 break-all font-mono text-xs text-stone-500 dark:text-stone-400"
                  >
                    {@telegram.session_id}
                  </p>
                </div>
              </div>
              <dl class="mt-5 space-y-3 border-t border-stone-200 pt-4 text-sm dark:border-white/10">
                <div class="flex items-center justify-between gap-4">
                  <dt class="text-stone-500 dark:text-stone-400">Trasporto</dt>
                  <dd class="font-semibold text-stone-800 dark:text-stone-200">ExGram / TDLib</dd>
                </div>
                <div class="flex items-center justify-between gap-4">
                  <dt class="text-stone-500 dark:text-stone-400">Fase</dt>
                  <dd
                    id="telegram-auth-state"
                    class="text-right font-semibold text-stone-800 dark:text-stone-200"
                  >
                    {auth_state_label(@telegram.auth_state)}
                  </dd>
                </div>
              </dl>
            </div>

            <div class="rounded-2xl border border-emerald-200 bg-emerald-50/70 p-5 text-sm leading-6 text-emerald-950 dark:border-emerald-500/20 dark:bg-emerald-500/[0.06] dark:text-emerald-100">
              <div class="flex items-center gap-2 font-bold">
                <.icon name="hero-shield-check" class="size-5" /> Dati sensibili
              </div>
              <p class="mt-2 text-emerald-900/75 dark:text-emerald-100/70">
                QR, codici e password Telegram restano transitori e non vengono scritti nel database o nei log.
              </p>
            </div>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp run_action(socket, operation, success_message) do
    case safe_transport_call(operation) do
      :ok ->
        {:noreply,
         socket
         |> assign_snapshot(fetch_snapshot())
         |> put_flash(:info, success_message)}

      {:error, :telegram_unavailable} ->
        {:noreply, put_flash(socket, :error, "Telegram non è disponibile. Riprova tra poco.")}

      _unexpected ->
        {:noreply, put_flash(socket, :error, "Telegram non è disponibile. Riprova tra poco.")}
    end
  end

  defp safe_transport_call(operation) do
    operation.()
  rescue
    _exception -> {:error, :telegram_unavailable}
  catch
    :exit, _reason -> {:error, :telegram_unavailable}
  end

  defp fetch_snapshot do
    Transport.snapshot()
  rescue
    _exception -> @default_snapshot
  catch
    :exit, _reason -> @default_snapshot
  end

  defp assign_snapshot(socket, snapshot) do
    telegram = Map.merge(@default_snapshot, snapshot)

    qr_svg =
      case telegram.qr_link do
        link when is_binary(link) ->
          case QR.render(link) do
            {:ok, svg} -> svg
            {:error, _reason} -> nil
          end

        _missing ->
          nil
      end

    socket
    |> assign(:telegram, telegram)
    |> assign(:qr_svg, qr_svg)
  end

  defp empty_form(name, field), do: to_form(%{field => ""}, as: name)

  defp normalize_phone(phone) when is_binary(phone) do
    phone
    |> String.trim()
    |> String.replace(~r/[\s().-]/, "")
  end

  defp normalize_phone(_phone), do: ""

  defp normalize_code(code) when is_binary(code), do: String.trim(code)
  defp normalize_code(_code), do: ""

  defp valid_phone?(phone), do: Regex.match?(~r/^\+[1-9]\d{6,14}$/, phone)

  defp valid_telegram_password?(password) do
    is_binary(password) and String.trim(password) != "" and byte_size(password) <= 1_024
  end

  defp submit_button_classes do
    "inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-xl bg-stone-950 px-4 py-2.5 text-sm font-bold text-white shadow-sm transition duration-200 hover:-translate-y-0.5 hover:bg-amber-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-600 disabled:pointer-events-none disabled:opacity-50 dark:bg-amber-400 dark:text-stone-950 dark:hover:bg-amber-300"
  end

  defp status_label(:connected), do: "Connesso"
  defp status_label(:authenticating), do: "Autenticazione"
  defp status_label(:connecting), do: "Connessione"
  defp status_label(:idle), do: "In attesa"
  defp status_label(_status), do: "Disconnesso"

  defp status_classes(:connected),
    do:
      "border-emerald-200 bg-emerald-50 text-emerald-800 dark:border-emerald-500/25 dark:bg-emerald-500/10 dark:text-emerald-300"

  defp status_classes(:authenticating),
    do:
      "border-amber-200 bg-amber-50 text-amber-800 dark:border-amber-500/25 dark:bg-amber-500/10 dark:text-amber-300"

  defp status_classes(:connecting),
    do:
      "border-sky-200 bg-sky-50 text-sky-800 dark:border-sky-500/25 dark:bg-sky-500/10 dark:text-sky-300"

  defp status_classes(_status),
    do:
      "border-stone-200 bg-stone-100 text-stone-700 dark:border-white/10 dark:bg-white/[0.05] dark:text-stone-300"

  defp status_dot_classes(:connected),
    do: "bg-emerald-500 shadow-[0_0_0_3px_rgba(16,185,129,0.15)]"

  defp status_dot_classes(:authenticating), do: "animate-pulse bg-amber-500"
  defp status_dot_classes(:connecting), do: "animate-pulse bg-sky-500"
  defp status_dot_classes(_status), do: "bg-stone-400"

  defp auth_state_label(:wait_phone_number), do: "Scelta accesso"
  defp auth_state_label(:requesting_qr), do: "Richiesta QR"
  defp auth_state_label(:wait_other_device_confirmation), do: "Scansione QR"
  defp auth_state_label(:wait_code), do: "Codice Telegram"
  defp auth_state_label(:submitting_phone), do: "Invio numero"
  defp auth_state_label(:submitting_code), do: "Verifica codice"
  defp auth_state_label(:wait_password), do: "Password 2FA"
  defp auth_state_label(:submitting_password), do: "Verifica 2FA"
  defp auth_state_label(:ready), do: "Autorizzata"
  defp auth_state_label(:starting), do: "Avvio"
  defp auth_state_label(:connecting), do: "Connessione"
  defp auth_state_label(_state), do: "Non disponibile"

  defp auth_state_description(:wait_phone_number),
    do: "Scegli il QR oppure continua con il numero di telefono."

  defp auth_state_description(:requesting_qr), do: "Telegram sta preparando un QR temporaneo."

  defp auth_state_description(:wait_other_device_confirmation),
    do: "Il QR è pronto per essere scansionato."

  defp auth_state_description(:wait_code), do: "Attendo il codice inviato da Telegram."
  defp auth_state_description(:wait_password), do: "È richiesta la password Telegram 2FA."
  defp auth_state_description(:ready), do: "La sessione è autorizzata e operativa."
  defp auth_state_description(_state), do: "Controllo lo stato della sessione ExGram."
end
