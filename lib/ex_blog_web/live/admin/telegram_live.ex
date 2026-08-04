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
     |> assign(:page_title, gettext("Telegram connection"))
     |> assign(
       :meta_description,
       gettext("Restricted management of the Spectre Telegram session.")
     )
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
    run_action(socket, &Transport.connect/0, gettext("Telegram reconnection started."))
  end

  def handle_event("request_qr", _params, socket) do
    run_action(socket, &Transport.request_qr/0, gettext("QR requested from Telegram."))
  end

  def handle_event("switch_account", _params, socket) do
    run_action(
      socket,
      &Transport.switch_account/0,
      gettext("Telegram logout started. You can enter the new number as soon as requested.")
    )
  end

  def handle_event("provide_phone", %{"telegram_phone" => params}, socket) do
    phone = params |> Map.get("phone", "") |> normalize_phone()

    if valid_phone?(phone) do
      socket = assign(socket, :phone_form, empty_form(:telegram_phone, "phone"))
      run_action(socket, fn -> Transport.provide_phone_number(phone) end, gettext("Number sent."))
    else
      {:noreply,
       socket
       |> assign(:phone_form, empty_form(:telegram_phone, "phone"))
       |> put_flash(
         :error,
         gettext("Enter a valid international number, for example +393331234567.")
       )}
    end
  end

  def handle_event("provide_code", %{"telegram_code" => params}, socket) do
    code = params |> Map.get("code", "") |> normalize_code()

    if Regex.match?(~r/^\d{3,10}$/, code) do
      socket = assign(socket, :code_form, empty_form(:telegram_code, "code"))
      run_action(socket, fn -> Transport.provide_auth_code(code) end, gettext("Code sent."))
    else
      {:noreply,
       socket
       |> assign(:code_form, empty_form(:telegram_code, "code"))
       |> put_flash(:error, gettext("Enter the numeric code received from Telegram."))}
    end
  end

  def handle_event("provide_password", %{"telegram_password" => params}, socket) do
    password = Map.get(params, "password", "")

    if valid_telegram_password?(password) do
      socket = assign(socket, :password_form, empty_form(:telegram_password, "password"))

      run_action(
        socket,
        fn -> Transport.provide_password(password) end,
        gettext("Verification password sent.")
      )
    else
      {:noreply,
       socket
       |> assign(:password_form, empty_form(:telegram_password, "password"))
       |> put_flash(:error, gettext("Enter the two-step verification password."))}
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
        class="mx-auto min-h-[calc(100vh-8rem)] max-w-6xl px-4 py-10 sm:px-6 lg:px-8"
      >
        <header class="mb-7 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p class="term-prompt text-[0.72rem] t-faint">spectre telegram status</p>
            <h1
              id="admin-telegram-heading"
              class="mt-3 text-2xl font-bold tracking-tight t-strong sm:text-3xl"
            >
              {gettext("Telegram connection")}
            </h1>
            <p class="mt-2 max-w-2xl text-[0.78rem] leading-6 t-faint">
              <span aria-hidden="true">// </span>{gettext(
                "Connect the account that controls Spectre and follow every TDLib authentication step in real time."
              )}
            </p>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <button id="telegram-refresh-button" type="button" phx-click="refresh" class="term-btn">
              <.icon name="hero-arrow-path" class="size-4 phx-click-loading:animate-spin" />
              {gettext("refresh")}
            </button>
            <.link
              id="admin-logout-link"
              href={~p"/admin/logout"}
              method="delete"
              class="term-btn border-transparent t-dim hover:t-strong"
            >
              exit
            </.link>
          </div>
        </header>

        <div class="grid gap-5 lg:grid-cols-[minmax(0,1fr)_19rem]">
          <main class="order-2 lg:order-1">
            <div class="term-window overflow-hidden">
              <div class="term-bar">
                <span class="term-dots" aria-hidden="true">
                  <span class="term-dot"></span>
                  <span class="term-dot"></span>
                  <span class="term-dot"></span>
                </span>
                <span class="term-title">tdlib — auth</span>
                <span
                  id="telegram-connection-status"
                  role="status"
                  aria-live="polite"
                  class={[
                    "ml-auto flex flex-none items-center gap-2",
                    status_classes(@telegram.connection_status)
                  ]}
                >
                  <span class={[
                    "size-1.5 rounded-full",
                    status_dot_classes(@telegram.connection_status)
                  ]}></span>
                  {status_label(@telegram.connection_status)}
                </span>
              </div>

              <div class="border-b border-dashed border-[color:var(--line)] px-5 py-4 sm:px-7">
                <h2 class="text-[0.92rem] font-bold t-strong">{gettext("Account pairing")}</h2>
                <p class="term-out mt-1.5 text-[0.75rem] t-faint">
                  {auth_state_description(@telegram.auth_state)}
                </p>
              </div>

              <div class="p-5 sm:p-7">
                <div
                  :if={@telegram.last_error?}
                  id="telegram-connection-error"
                  role="alert"
                  class="mb-6 flex items-start gap-3 border border-[color:var(--line-strong)] bg-[color:var(--surface-bar)] px-4 py-3 text-[0.78rem] leading-6 t-body"
                >
                  <span class="t-faint" aria-hidden="true">!</span>
                  <p>
                    {gettext(
                      "Telegram reported a problem. You can refresh the status or retry the connection."
                    )}
                  </p>
                </div>

                <div
                  :if={@telegram.connection_status == :connected}
                  id="telegram-connected-panel"
                  class="py-8"
                >
                  <p class="term-prompt text-[0.75rem] t-dim">telegram auth --check</p>
                  <p class="term-out mt-2 text-[0.78rem] t-body">
                    {gettext("OK — session authorized")}
                  </p>
                  <h2 class="mt-6 text-xl font-bold tracking-tight t-strong">
                    {gettext("Telegram is connected")}
                  </h2>
                  <p class="mt-2 max-w-lg text-[0.78rem] leading-6 t-faint">
                    <span aria-hidden="true">// </span>{gettext(
                      "The TDLib session is authorized and ready to receive messages from the configured administrator."
                    )}
                  </p>
                  <div class="mt-6 border-t border-dashed border-[color:var(--line)] pt-5">
                    <p class="max-w-lg text-[0.75rem] leading-6 t-faint">
                      <span aria-hidden="true">// </span>{gettext(
                        "To use another number, log out this Telegram session and start a new pairing."
                      )}
                    </p>
                    <button
                      id="telegram-switch-account-button"
                      type="button"
                      phx-click="switch_account"
                      phx-disable-with={gettext("Disconnecting…")}
                      data-confirm={
                        gettext("Disconnect the current Telegram account and pair another number?")
                      }
                      class="term-btn mt-4"
                    >
                      <.icon name="hero-arrow-path-rounded-square" class="size-4" />
                      {gettext("Use another phone number")}
                    </button>
                  </div>
                </div>

                <div
                  :if={@telegram.auth_state == :switching_account}
                  id="telegram-switching-account-panel"
                  class="py-12"
                  role="status"
                >
                  <p class="term-prompt text-[0.75rem] t-dim">telegram logout</p>
                  <p class="mt-3 flex items-center gap-2 text-[0.8rem] t-strong">
                    {gettext("Preparing a new Telegram login")} <.cursor />
                  </p>
                  <p class="mt-2 text-[0.75rem] t-faint">
                    <span aria-hidden="true">// </span>{gettext(
                      "The phone-number form will appear when TDLib is ready."
                    )}
                  </p>
                </div>

                <div
                  :if={@telegram.auth_state == :wait_phone_number}
                  id="telegram-pairing-options"
                  class="grid gap-4 md:grid-cols-2"
                >
                  <article class="term-window term-window--raised flex flex-col overflow-hidden">
                    <div class="term-bar">
                      <span class="term-title">$ telegram login --qr</span>
                      <span class="ml-auto flex-none t-faint">{gettext("recommended")}</span>
                    </div>
                    <div class="term-body flex flex-1 flex-col">
                      <h3 class="text-[0.92rem] font-bold t-strong">
                        {gettext("Pair with a QR code")}
                      </h3>
                      <p class="mt-2 flex-1 text-[0.75rem] leading-6 t-faint">
                        <span aria-hidden="true">// </span>{gettext(
                          "Open Telegram on an already authenticated device and scan the code."
                        )}
                      </p>
                      <button
                        id="telegram-request-qr-button"
                        type="button"
                        phx-click="request_qr"
                        phx-disable-with={gettext("Requesting…")}
                        class="term-btn term-btn--primary mt-5 w-full"
                      >
                        <.icon name="hero-qr-code" class="size-4" /> {gettext("Generate the QR")}
                      </button>
                    </div>
                  </article>

                  <article class="term-window term-window--raised overflow-hidden">
                    <div class="term-bar">
                      <span class="term-title">$ telegram login --phone</span>
                    </div>
                    <div class="term-body">
                      <h3 class="text-[0.92rem] font-bold t-strong">
                        {gettext("Use the phone number")}
                      </h3>
                      <p class="mt-2 text-[0.75rem] leading-6 t-faint">
                        <span aria-hidden="true">// </span>{gettext(
                          "Alternatively, enter the international number linked to the account."
                        )}
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
                          label={gettext("phone number")}
                          placeholder="+393331234567"
                          autocomplete="tel"
                          required
                        />
                        <.button
                          id="telegram-phone-submit"
                          type="submit"
                          class={submit_button_classes()}
                        >
                          {gettext("Continue with the number")}
                        </.button>
                      </.form>
                    </div>
                  </article>
                </div>

                <div
                  :if={@telegram.auth_state == :requesting_qr}
                  id="telegram-qr-loading"
                  class="py-12"
                  role="status"
                >
                  <p class="term-prompt text-[0.75rem] t-dim">telegram qr --request</p>
                  <p class="mt-3 flex items-center gap-2 text-[0.8rem] t-strong">
                    {gettext("Generating the QR")} <.cursor />
                  </p>
                  <p class="mt-2 text-[0.75rem] t-faint">
                    <span aria-hidden="true">// </span>{gettext(
                      "Waiting for the temporary link from Telegram…"
                    )}
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
                      aria-label={gettext("QR code to pair Telegram")}
                      class="aspect-square overflow-hidden rounded border border-[color:var(--line-strong)] bg-white p-4 [&_svg]:block [&_svg]:size-full"
                    >
                      {raw(@qr_svg)}
                    </div>
                    <div
                      :if={!@qr_svg}
                      id="telegram-qr-unavailable"
                      class="flex aspect-square items-center justify-center rounded border border-dashed border-[color:var(--line-strong)] bg-[color:var(--surface-bar)] p-6 text-center text-[0.75rem] leading-6 t-dim"
                    >
                      {gettext("The QR could not be rendered. Request a new one.")}
                    </div>
                  </div>

                  <div>
                    <p class="term-prompt text-[0.72rem] t-faint">telegram qr --show</p>
                    <h2 class="mt-3 text-xl font-bold tracking-tight t-strong">
                      {gettext("Scan with Telegram")}
                    </h2>
                    <ol class="mt-5 space-y-3 text-[0.78rem] leading-6 t-dim">
                      <li class="flex gap-3">
                        <span aria-hidden="true" class="w-6 shrink-0 t-faint">[1]</span>
                        {gettext("Open Telegram on the already authenticated phone.")}
                      </li>
                      <li class="flex gap-3">
                        <span aria-hidden="true" class="w-6 shrink-0 t-faint">[2]</span>
                        {gettext("Go to Settings, Devices, Link desktop device.")}
                      </li>
                      <li class="flex gap-3">
                        <span aria-hidden="true" class="w-6 shrink-0 t-faint">[3]</span>
                        {gettext("Frame the code and wait for the confirmation on this page.")}
                      </li>
                    </ol>
                    <button
                      id="telegram-renew-qr-button"
                      type="button"
                      phx-click="request_qr"
                      class="term-btn mt-6"
                    >
                      <.icon name="hero-arrow-path" class="size-4" /> {gettext("Generate a new QR")}
                    </button>
                  </div>
                </div>

                <div
                  :if={@telegram.auth_state in [:wait_code, :submitting_phone, :submitting_code]}
                  id="telegram-code-panel"
                  class="mx-auto max-w-md py-6"
                >
                  <p class="term-prompt text-[0.72rem] t-faint">telegram auth --code</p>
                  <h2 class="mt-3 text-xl font-bold tracking-tight t-strong">
                    {gettext("Enter the code")}
                  </h2>
                  <p class="mt-2 text-[0.78rem] leading-6 t-faint">
                    <span aria-hidden="true">// </span>{gettext(
                      "Telegram sent a code to the account. ExBlog will not store it."
                    )}
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
                      label={gettext("telegram code")}
                      autocomplete="one-time-code"
                      pattern="[0-9]{3,10}"
                      required
                    />
                    <.button
                      id="telegram-code-submit"
                      type="submit"
                      class={submit_button_classes()}
                    >
                      {gettext("Verify code")}
                    </.button>
                  </.form>
                </div>

                <div
                  :if={@telegram.auth_state in [:wait_password, :submitting_password]}
                  id="telegram-password-panel"
                  class="mx-auto max-w-md py-6"
                >
                  <p class="term-prompt text-[0.72rem] t-faint">telegram auth --2fa</p>
                  <h2 class="mt-3 text-xl font-bold tracking-tight t-strong">
                    {gettext("Two-step verification")}
                  </h2>
                  <p class="mt-2 text-[0.78rem] leading-6 t-faint">
                    <span aria-hidden="true">// </span>{gettext(
                      "Enter the Telegram 2FA password. It is forwarded straight to TDLib and never stored."
                    )}
                  </p>
                  <p
                    :if={@telegram.password_hint}
                    id="telegram-password-hint"
                    class="mt-4 border-l-2 border-[color:var(--line-strong)] bg-[color:var(--surface-bar)] px-3 py-2 text-[0.75rem] t-dim"
                  >
                    {gettext("hint")}: {@telegram.password_hint}
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
                      label={gettext("telegram password")}
                      autocomplete="current-password"
                      required
                    />
                    <.button
                      id="telegram-password-submit"
                      type="submit"
                      class={submit_button_classes()}
                    >
                      {gettext("Complete the verification")}
                    </.button>
                  </.form>
                </div>

                <div
                  :if={@telegram.auth_state in [:starting, :connecting, :unavailable, :disconnected]}
                  id="telegram-disconnected-panel"
                  class="py-10"
                >
                  <p class="term-prompt text-[0.75rem] t-dim">telegram status</p>
                  <p class="mt-2 text-[0.8rem] t-body">{gettext("connection not ready")}</p>
                  <h2 class="mt-6 text-xl font-bold tracking-tight t-strong">
                    {gettext("TDLib session not started")}
                  </h2>
                  <p class="mt-2 max-w-md text-[0.78rem] leading-6 t-faint">
                    <span aria-hidden="true">// </span>{gettext(
                      "Start or retry the session to receive the next authentication state."
                    )}
                  </p>
                  <button
                    id="telegram-connect-button"
                    type="button"
                    phx-click="connect"
                    phx-disable-with={gettext("Connecting…")}
                    class="term-btn term-btn--primary mt-6"
                  >
                    <.icon name="hero-signal" class="size-4" /> {gettext("Connect Telegram")}
                  </button>
                </div>
              </div>
            </div>
          </main>

          <aside class="order-1 space-y-4 lg:order-2" aria-label={gettext("Connection details")}>
            <div class="term-window overflow-hidden">
              <div class="term-bar">
                <span class="term-title">$ telegram session --info</span>
              </div>
              <dl class="term-body space-y-2.5 text-[0.72rem] leading-5">
                <div class="flex gap-3">
                  <dt class="w-20 shrink-0 t-faint">session</dt>
                  <dd id="telegram-session-id" class="min-w-0 break-all t-dim">
                    {@telegram.session_id}
                  </dd>
                </div>
                <div class="flex gap-3">
                  <dt class="w-20 shrink-0 t-faint">transport</dt>
                  <dd class="t-dim">ExGram / TDLib</dd>
                </div>
                <div class="flex gap-3">
                  <dt class="w-20 shrink-0 t-faint">phase</dt>
                  <dd id="telegram-auth-state" class="t-strong">
                    {auth_state_label(@telegram.auth_state)}
                  </dd>
                </div>
              </dl>
            </div>

            <div class="term-window overflow-hidden">
              <div class="term-bar">
                <span class="term-title">$ cat SECURITY.md</span>
              </div>
              <div class="term-body text-[0.72rem] leading-5 t-faint">
                <p class="t-dim">{gettext("Sensitive data")}</p>
                <p class="mt-2">
                  <span aria-hidden="true">// </span>{gettext(
                    "Telegram QR codes, codes and passwords stay transient and are never written to the database or the logs."
                  )}
                </p>
              </div>
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
        {:noreply, put_flash(socket, :error, gettext("Telegram is unavailable. Try again soon."))}

      _unexpected ->
        {:noreply, put_flash(socket, :error, gettext("Telegram is unavailable. Try again soon."))}
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

  defp submit_button_classes, do: "term-btn term-btn--primary mt-2 w-full"

  defp status_label(:connected), do: gettext("connected")
  defp status_label(:authenticating), do: gettext("auth")
  defp status_label(:connecting), do: gettext("connecting")
  defp status_label(:idle), do: gettext("idle")
  defp status_label(_status), do: gettext("disconnected")

  defp status_classes(:connected), do: "t-strong"
  defp status_classes(status) when status in [:authenticating, :connecting], do: "t-dim"
  defp status_classes(_status), do: "t-faint"

  defp status_dot_classes(:connected),
    do: "bg-[color:var(--fg-strong)] shadow-[0_0_0_3px_rgba(255,255,255,0.08)]"

  defp status_dot_classes(status) when status in [:authenticating, :connecting],
    do: "animate-pulse bg-[color:var(--fg-dim)]"

  defp status_dot_classes(_status), do: "bg-[color:var(--fg-faint)]"

  defp auth_state_label(:wait_phone_number), do: gettext("Login choice")
  defp auth_state_label(:requesting_qr), do: gettext("QR request")
  defp auth_state_label(:wait_other_device_confirmation), do: gettext("QR scan")
  defp auth_state_label(:wait_code), do: gettext("Telegram code")
  defp auth_state_label(:submitting_phone), do: gettext("Sending number")
  defp auth_state_label(:submitting_code), do: gettext("Verifying code")
  defp auth_state_label(:wait_password), do: gettext("2FA password")
  defp auth_state_label(:submitting_password), do: gettext("Verifying 2FA")
  defp auth_state_label(:ready), do: gettext("Authorized")
  defp auth_state_label(:switching_account), do: gettext("Changing account")
  defp auth_state_label(:starting), do: gettext("Starting")
  defp auth_state_label(:connecting), do: gettext("Connecting")
  defp auth_state_label(_state), do: gettext("Unavailable")

  defp auth_state_description(:wait_phone_number),
    do: gettext("Pick the QR code or continue with the phone number.")

  defp auth_state_description(:requesting_qr),
    do: gettext("Telegram is preparing a temporary QR code.")

  defp auth_state_description(:wait_other_device_confirmation),
    do: gettext("The QR code is ready to be scanned.")

  defp auth_state_description(:wait_code), do: gettext("Waiting for the code sent by Telegram.")

  defp auth_state_description(:wait_password),
    do: gettext("The Telegram 2FA password is required.")

  defp auth_state_description(:ready), do: gettext("The session is authorized and running.")

  defp auth_state_description(:switching_account),
    do: gettext("The current account is being disconnected before a new login.")

  defp auth_state_description(_state), do: gettext("Checking the ExGram session status.")
end
