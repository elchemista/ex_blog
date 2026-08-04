defmodule ExBlogWeb.Showcase do
  @moduledoc """
  Home page sections presenting the Spectre ecosystem.

  Every claim rendered here is sourced from the upstream documentation:
  `deps/spectre/README.md` for the safety boundary and the design credo, each
  `deps/spectre_*/README.md` for the library summaries, and
  `docs/spectre-editorial-showcase.md` for the request path this site follows.
  """

  use Phoenix.Component
  use Gettext, backend: ExBlogWeb.Gettext

  @spectre_repo "elchemista/spectre"
  @blog_repo "elchemista/ex_blog"

  @doc "Returns the GitHub URL of the open-source repository behind this site."
  def blog_repo_url, do: "https://github.com/" <> @blog_repo
  def blog_repo, do: @blog_repo
  def spectre_repo, do: @spectre_repo
  def spectre_repo_url, do: "https://github.com/" <> @spectre_repo

  @doc """
  The whole showcase: credo, request path, library catalog and rationale.
  """
  def spectre_showcase(assigns) do
    assigns = assign(assigns, :libraries, libraries())

    ~H"""
    <section id="spectre-showcase" class="mt-16 space-y-6">
      <div class="flex flex-wrap items-end justify-between gap-4 border-b border-[color:var(--line)] pb-4">
        <div>
          <p class="term-prompt text-[0.72rem] t-faint">man spectre</p>
          <h2 class="mt-3 text-xl font-bold tracking-tight t-strong sm:text-2xl">
            {gettext("What Spectre is")}
          </h2>
        </div>
        <a
          href={spectre_repo_url()}
          rel="noopener noreferrer"
          class="term-chip"
        >
          github.com/{spectre_repo()}
        </a>
      </div>

      <div class="term-window overflow-hidden">
        <div class="term-bar">
          <span class="term-dots" aria-hidden="true">
            <span class="term-dot"></span>
            <span class="term-dot"></span>
            <span class="term-dot"></span>
          </span>
          <span class="term-title">spectre/README.md</span>
        </div>
        <div class="term-body p-5 sm:p-7">
          <p class="text-[0.85rem] leading-7 t-body sm:text-[0.9rem]">
            {gettext(
              "Spectre is an OTP-native Elixir runtime for agents whose routing, state, policies and side effects stay explicit. It treats an agent the way OTP treats a system: supervised processes, one canonical owner for every piece of state, explicit messages at every boundary, and recovery designed in from the start."
            )}
          </p>

          <p class="term-prompt mt-8 text-[0.72rem] t-faint">cat POLICY.md</p>
          <p class="mt-3 text-[0.78rem] t-dim">
            {gettext("Spectre is intentionally built around a safety boundary:")}
          </p>
          <ul class="mt-4 space-y-2 text-[0.78rem] leading-6 t-body">
            <li :for={rule <- safety_boundary()} class="flex gap-3">
              <span class="flex-none t-faint" aria-hidden="true">-</span>
              <span>{rule}</span>
            </li>
          </ul>

          <p class="mt-8 border-l-2 border-[color:var(--line-strong)] pl-4 text-[0.85rem] leading-7 t-strong">
            {gettext("A Spectre agent should read like a map, not a magic trick.")}
          </p>
        </div>
      </div>

      <div class="grid gap-6 lg:grid-cols-2">
        <div class="term-window overflow-hidden">
          <div class="term-bar">
            <span class="term-dots" aria-hidden="true">
              <span class="term-dot"></span>
              <span class="term-dot"></span>
              <span class="term-dot"></span>
            </span>
            <span class="term-title">$ spectre trace --this-site</span>
          </div>
          <div class="term-body">
            <p class="text-[0.78rem] leading-6 t-dim">
              <span class="t-faint" aria-hidden="true">// </span>{gettext(
                "This site is the demo. An article is written by talking to the agent, and every repository change is approved before it happens."
              )}
            </p>
            <div class="mt-5 overflow-x-auto">
              <div class="min-w-max text-[0.7rem] leading-[1.7] t-faint">
                <div :for={line <- request_path()}>
                  <%!-- whitespace-pre keeps the tree indentation, which HTML would collapse --%>
                  <span class="whitespace-pre t-dim">{line.node}</span>
                  <span :if={line.note} class="t-faint">— {line.note}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="term-window overflow-hidden">
          <div class="term-bar">
            <span class="term-dots" aria-hidden="true">
              <span class="term-dot"></span>
              <span class="term-dot"></span>
              <span class="term-dot"></span>
            </span>
            <span class="term-title">$ why --like-this</span>
          </div>
          <div class="term-body space-y-4 text-[0.78rem] leading-6 t-dim">
            <p>
              <span class="t-faint" aria-hidden="true">// </span>{gettext(
                "Routing is a dial, not a dogma: the same agent can decide with plain regex, with a dataset, or with a full LLM classifier. The lifecycle around that decision stays deterministic either way."
              )}
            </p>
            <p>
              <span class="t-faint" aria-hidden="true">// </span>{gettext(
                "The design borrows from Phoenix routers, Ecto schemas, Oban workers, Broadway pipelines and OTP supervision trees, so the stable shape of an agent fits in one readable module."
              )}
            </p>
            <p>
              <span class="t-faint" aria-hidden="true">// </span>{gettext(
                "This blog has no SQL database. GitHub is the canonical content store, Phoenix serves a fast ETS projection, and the agent may propose a change but never writes without approval."
              )}
            </p>
            <p class="border-t border-dashed border-[color:var(--line)] pt-4">
              <a
                href={blog_repo_url()}
                rel="noopener noreferrer"
                class="t-strong underline decoration-dashed underline-offset-4 transition hover:t-invert"
              >
                github.com/{blog_repo()}
              </a>
              <span class="t-faint"> — {gettext("the source of this site, open source")}</span>
            </p>
          </div>
        </div>
      </div>

      <div class="flex flex-wrap items-end justify-between gap-4 border-b border-[color:var(--line)] pb-4 pt-6">
        <div>
          <p class="term-prompt text-[0.72rem] t-faint">ls -1 deps/spectre*</p>
          <h2 class="mt-3 text-xl font-bold tracking-tight t-strong sm:text-2xl">
            {gettext("The ecosystem")}
          </h2>
        </div>
        <span class="term-chip">
          {ngettext("%{count} library", "%{count} libraries", length(@libraries))}
        </span>
      </div>

      <div class="grid gap-5 md:grid-cols-2">
        <a
          :for={library <- @libraries}
          href={"https://github.com/#{library.repo}"}
          rel="noopener noreferrer"
          class="term-window term-window--link group block overflow-hidden"
        >
          <div class="term-bar">
            <span class="term-dots" aria-hidden="true">
              <span class="term-dot"></span>
              <span class="term-dot"></span>
              <span class="term-dot"></span>
            </span>
            <span class="term-title">{library.name}</span>
            <span class="ml-auto flex-none t-faint">{library.role}</span>
          </div>
          <div class="term-body">
            <p class="text-[0.78rem] leading-6 t-dim">{library.tagline}</p>
            <p class="mt-4 flex items-center gap-1.5 border-t border-dashed border-[color:var(--line)] pt-3 text-[0.68rem] t-faint">
              github.com/{library.repo}
              <span class="transition-transform group-hover:translate-x-1" aria-hidden="true">→</span>
            </p>
          </div>
        </a>
      </div>
    </section>
    """
  end

  defp safety_boundary do
    [
      gettext("models and routes may propose work"),
      gettext("protected work must pass a deterministic policy"),
      gettext("approval changes state but does not execute the work"),
      gettext("execution happens only through an explicit host call"),
      gettext("every terminal outcome is returned as data")
    ]
  end

  defp request_path do
    [
      %{node: "telegram / mcp", note: gettext("authenticated administrator")},
      %{node: "└── spectre_beam", note: gettext("channel boundary, identity")},
      %{node: "    └── spectre", note: gettext("routing, state, policy, effects")},
      %{node: "        ├── skills", note: gettext("reader · editorial · operations")},
      %{node: "        ├── spectre_prism", note: gettext("fast · balanced · deep tier")},
      %{node: "        ├── spectre_kinetic", note: gettext("action language → typed action")},
      %{node: "        ├── spectre_lens", note: gettext("audits the rendered page")},
      %{node: "        └── policy", note: gettext("confirmation → effect")},
      %{node: "            └── writer → git → ets", note: gettext("the page you are reading")}
    ]
  end

  defp libraries do
    [
      %{
        name: "spectre",
        repo: "elchemista/spectre",
        role: "runtime",
        tagline:
          gettext(
            "The agent runtime: supervised processes, one owner per piece of state, and policies that decide what may actually happen."
          )
      },
      %{
        name: "spectre_beam",
        repo: "elchemista/spectre_beam",
        role: "channels",
        tagline:
          gettext(
            "The external-channel boundary. It normalizes provider events, keeps conversation affinity and delivers messages idempotently."
          )
      },
      %{
        name: "spectre_prism",
        repo: "elchemista/spectre_prism",
        role: "models",
        tagline:
          gettext(
            "Picks a cognitive profile per request across OpenAI, OpenRouter, Ollama and Gemini, enforcing privacy, context, cost and latency limits before the call."
          )
      },
      %{
        name: "spectre_kinetic",
        repo: "elchemista/spectre_kinetic",
        role: "planning",
        tagline:
          gettext(
            "Elixir-first planning: it turns Action Language into validated function-call candidates instead of trusting free-form model output."
          )
      },
      %{
        name: "spectre_lens",
        repo: "elchemista/spectre_lens",
        role: "browser",
        tagline:
          gettext(
            "Agent-first, backend-neutral browser perception, so the agent can audit the pages it publishes."
          )
      }
    ]
  end
end
