// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/ex_blog"
import topbar from "../vendor/topbar"
import CookieConsent from "../vendor/cookieconsent.umd"

// The blog is designed black-first: dark is the default and light is opt-in.
const preferredTheme = () => "dark"

const storedTheme = () => {
  try {
    return window.localStorage.getItem("ex-blog:theme")
  } catch (_error) {
    return null
  }
}

const applyTheme = theme => {
  const resolved = theme === "dark" || theme === "light" ? theme : preferredTheme()
  document.documentElement.dataset.theme = resolved
  document.documentElement.classList.toggle("cc--darkmode", resolved === "dark")
  document.querySelectorAll("[data-theme-toggle]").forEach(button => {
    button.setAttribute("aria-pressed", String(resolved === "dark"))
  })
}

applyTheme(storedTheme())

document.addEventListener("click", event => {
  const toggle = event.target.closest("[data-theme-toggle]")
  if (!toggle) return

  const nextTheme = document.documentElement.dataset.theme === "dark" ? "light" : "dark"

  try {
    window.localStorage.setItem("ex-blog:theme", nextTheme)
  } catch (_error) {
    // A private browser context may make localStorage unavailable.
  }

  applyTheme(nextTheme)
})

window.addEventListener("storage", event => {
  if (event.key === "ex-blog:theme") applyTheme(event.newValue)
})

// Controller-rendered pages have no LiveView root, so their phx-click bindings
// never run. Dismiss those flashes here; inside a LiveView the server command
// stays in charge.
document.addEventListener("click", event => {
  const dismiss = event.target.closest("[data-flash-dismiss]")
  if (!dismiss || dismiss.closest("[data-phx-session]")) return

  dismiss.closest("[data-flash]")?.remove()
})

const siteDomain = "spectre.elchemista.com"
const documentLanguage = document.documentElement.lang.toLowerCase().split("-")[0]
const consentLanguage = ["it", "en"].includes(documentLanguage) ? documentLanguage : "it"

CookieConsent.run({
  cookie: {
    name: "spectre_cookie_consent",
    expiresAfterDays: 182,
    sameSite: "Lax",
  },
  guiOptions: {
    consentModal: {
      layout: "box",
      position: "bottom right",
      equalWeightButtons: true,
      flipButtons: false,
    },
    preferencesModal: {
      layout: "box",
      position: "right",
      equalWeightButtons: true,
      flipButtons: false,
    },
  },
  categories: {
    necessary: {
      readOnly: true,
    },
    analytics: {},
  },
  language: {
    default: consentLanguage,
    translations: {
      it: {
        consentModal: {
          title: "Cookie e privacy su " + siteDomain,
          description:
            "Usiamo cookie necessari per il funzionamento e, solo con il tuo consenso, eventuali cookie analitici. Puoi accettare, rifiutare quelli facoltativi o scegliere nel dettaglio.",
          acceptAllBtn: "Accetta tutto",
          acceptNecessaryBtn: "Solo necessari",
          showPreferencesBtn: "Gestisci preferenze",
          footer:
            '<a href="/it/cookies-policy">Cookie Policy</a>\n<a href="/it/privacy-policy">Privacy Policy</a>\n<a href="/it/gdpr-policy">GDPR</a>',
        },
        preferencesModal: {
          title: "Preferenze cookie e GDPR",
          acceptAllBtn: "Accetta tutto",
          acceptNecessaryBtn: "Solo necessari",
          savePreferencesBtn: "Salva preferenze",
          closeIconLabel: "Chiudi",
          serviceCounterLabel: "Servizi",
          sections: [
            {
              title: "Come usiamo i cookie",
              description:
                "I cookie essenziali mantengono il sito sicuro e ricordano la tua scelta. Le categorie facoltative restano spente finché non le autorizzi.",
            },
            {
              title:
                '<span>Cookie necessari</span> <span class="pm__badge">Sempre attivi</span>',
              description:
                "Servono per sicurezza, sessioni protette e memorizzazione del consenso. Non possono essere disattivati dal pannello.",
              linkedCategory: "necessary",
            },
            {
              title: "Cookie analitici",
              description:
                "Aiutano a capire come viene utilizzato il sito. Il bundle pubblico attuale non carica servizi analitici di terze parti.",
              linkedCategory: "analytics",
            },
            {
              title: "Altre informazioni",
              description:
                '<a class="cc__link" href="/it/cookies-policy">Leggi la Cookie Policy</a> oppure <a class="cc__link" href="mailto:elchemista@gmail.com">contattaci</a>.',
            },
          ],
        },
      },
      en: {
        consentModal: {
          title: "Cookies and privacy on " + siteDomain,
          description:
            "We use necessary cookies for operation and, only with your consent, optional analytics cookies. You can accept, reject optional cookies, or choose in detail.",
          acceptAllBtn: "Accept all",
          acceptNecessaryBtn: "Necessary only",
          showPreferencesBtn: "Manage preferences",
          footer:
            '<a href="/en/cookies-policy">Cookie Policy</a>\n<a href="/en/privacy-policy">Privacy Policy</a>\n<a href="/en/gdpr-policy">GDPR</a>',
        },
        preferencesModal: {
          title: "Cookie and GDPR preferences",
          acceptAllBtn: "Accept all",
          acceptNecessaryBtn: "Necessary only",
          savePreferencesBtn: "Save preferences",
          closeIconLabel: "Close",
          serviceCounterLabel: "Services",
          sections: [
            {
              title: "How we use cookies",
              description:
                "Essential cookies keep the site secure and remember your choice. Optional categories stay disabled until you authorize them.",
            },
            {
              title:
                '<span>Necessary cookies</span> <span class="pm__badge">Always enabled</span>',
              description:
                "They support security, protected sessions, and consent storage and cannot be disabled in this panel.",
              linkedCategory: "necessary",
            },
            {
              title: "Analytics cookies",
              description:
                "They help understand how the site is used. The current public bundle does not load third-party analytics services.",
              linkedCategory: "analytics",
            },
            {
              title: "More information",
              description:
                '<a class="cc__link" href="/en/cookies-policy">Read the Cookie Policy</a> or <a class="cc__link" href="mailto:elchemista@gmail.com">contact us</a>.',
            },
          ],
        },
      },
    },
  },
})

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#f5f5f7"}, shadowColor: "rgba(0, 0, 0, .6)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
