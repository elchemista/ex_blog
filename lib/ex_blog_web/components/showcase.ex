defmodule ExBlogWeb.Showcase do
  @moduledoc """
  Home page sections presenting the Spectre ecosystem.

  Every claim rendered here is sourced, not invented:

    * the definition, philosophy, safety boundary, reflective runtime and DSL
      example come from the published `spectre` 0.3.2 documentation;
    * each library summary comes from its own GitHub description
      (`api.github.com/users/elchemista/repos`, checked 2026-08-16);
    * the request path comes from `docs/spectre-editorial-showcase.md`;
    * the compatibility matrix is not written here at all. It is the daily
      `spectre_ecosystem` report, refreshed by `ExBlog.Ecosystem` and passed in
      as the `ecosystem` attribute.

  Every `repo` below was verified to resolve on github.com. Re-check before
  adding one: a card links straight to it, so a private or renamed repository
  sends visitors to a 404.
  """

  use Phoenix.Component
  use Gettext, backend: ExBlogWeb.Gettext

  @spectre_repo "elchemista/spectre"
  @blog_repo "elchemista/ex_blog"
  # The released version this page describes. Keep it here only: the chip, the
  # documentation link and the reflective-runtime paragraph all read it, so a
  # release bump is a one-line change.
  @spectre_version "0.3.2"
  @spectre_hexdocs_url "https://hexdocs.pm/spectre/#{@spectre_version}"
  @ecosystem_status_url "https://elchemista.github.io/spectre_ecosystem/"

  @doc "Returns the GitHub URL of the open-source repository behind this site."
  def blog_repo_url, do: "https://github.com/" <> @blog_repo
  def blog_repo, do: @blog_repo
  def spectre_repo, do: @spectre_repo
  def spectre_repo_url, do: "https://github.com/" <> @spectre_repo
  def spectre_version, do: @spectre_version
  def spectre_hexdocs_url, do: @spectre_hexdocs_url
  def ecosystem_status_url, do: @ecosystem_status_url

  @doc """
  The whole showcase: what Spectre is, a DSL sample, the request path this site
  follows, the rationale, the library catalog, and the compatibility matrix.
  """
  attr :ecosystem, :any,
    default: nil,
    doc:
      "an `ExBlog.Ecosystem.Snapshot`, or nil to leave the compatibility section out until the first refresh lands"

  def spectre_showcase(assigns) do
    assigns =
      assigns
      |> assign(:libraries, libraries())
      |> assign(:dsl_example, dsl_example())
      |> assign(:evolution_path, evolution_path())

    ~H"""
    <section id="spectre-showcase" class="mt-16 space-y-6">
      <div class="flex flex-wrap items-end justify-between gap-4 border-b border-[color:var(--line)] pb-4">
        <div>
          <p class="term-prompt text-[0.72rem] t-faint">man spectre</p>
          <h2 class="mt-3 text-xl font-bold tracking-tight t-strong sm:text-2xl">
            {gettext("The Spectre philosophy")}
          </h2>
        </div>
        <div class="flex flex-wrap gap-2">
          <a href={spectre_hexdocs_url()} rel="noopener noreferrer" class="term-chip">
            hex · {spectre_version()}
          </a>
          <a href={spectre_repo_url()} rel="noopener noreferrer" class="term-chip">
            github.com/{spectre_repo()}
          </a>
        </div>
      </div>

      <div class="term-window overflow-hidden">
        <div class="term-bar">
          <span class="term-dots" aria-hidden="true">
            <span class="term-dot"></span>
            <span class="term-dot"></span>
            <span class="term-dot"></span>
          </span>
          <span class="term-title">spectre/README.md</span>
          <span class="ml-auto hidden flex-none t-faint sm:block">S.P.E.C.T.R.E</span>
        </div>
        <div class="term-body p-5 sm:p-7">
          <p class="text-[0.85rem] leading-7 t-body sm:text-[0.9rem]">
            {gettext(
              "An agent is a supervised system, not a prompt or a costume for a model. Spectre gives each agent one canonical owner for state, explicit messages at every boundary, and recovery designed in from the start — the way OTP treats everything else."
            )}
          </p>

          <div class="mt-7 grid gap-4 md:grid-cols-3">
            <div
              id="spectre-philosophy-proposal"
              class="border-l border-[color:var(--line-strong)] pl-4"
            >
              <p class="text-[0.72rem] font-bold t-strong">
                {gettext("The model proposes")}
              </p>
              <p class="mt-2 text-[0.72rem] leading-5 t-dim">
                {gettext(
                  "It cannot skip policy, invent authority, or execute a side effect by itself."
                )}
              </p>
            </div>
            <div
              id="spectre-philosophy-routing"
              class="border-l border-[color:var(--line-strong)] pl-4"
            >
              <p class="text-[0.72rem] font-bold t-strong">
                {gettext("Routing is a dial")}
              </p>
              <p class="mt-2 text-[0.72rem] leading-5 t-dim">
                {gettext(
                  "Choose regex, semantic evidence, or a model; the lifecycle after that choice stays deterministic."
                )}
              </p>
            </div>
            <div id="spectre-philosophy-data" class="border-l border-[color:var(--line-strong)] pl-4">
              <p class="text-[0.72rem] font-bold t-strong">
                {gettext("Durable behavior is data")}
              </p>
              <p class="mt-2 text-[0.72rem] leading-5 t-dim">
                {gettext(
                  "Runtime-authored skills and proposals can reference only operations already registered by the host; data never becomes executable code."
                )}
              </p>
            </div>
          </div>

          <p class="term-prompt mt-8 text-[0.72rem] t-faint">cat POLICY.md</p>
          <p class="mt-3 text-[0.78rem] t-dim">
            {gettext("Anything protected crosses one boundary:")}
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

      <div class="term-window overflow-hidden">
        <div class="term-bar">
          <span class="term-dots" aria-hidden="true">
            <span class="term-dot"></span>
            <span class="term-dot"></span>
            <span class="term-dot"></span>
          </span>
          <span class="term-title">support_agent.ex</span>
          <span class="ml-auto flex-none t-faint">elixir</span>
        </div>
        <div class="term-body p-5 sm:p-7">
          <p class="text-[0.78rem] leading-6 t-dim">
            <span class="t-faint" aria-hidden="true">// </span>{gettext(
              "The whole agent is one module: the model, the router, a protected action, and the policy guarding it."
            )}
          </p>
          <pre class="term-code mt-5" data-language="elixir"><code>{@dsl_example}</code></pre>
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
                "Every article below arrived through this path."
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
                "Routing is a dial, not a dogma: regex, a dataset, or a full LLM classifier. What happens after the decision stays deterministic."
              )}
            </p>
            <p>
              <span class="t-faint" aria-hidden="true">// </span>{gettext(
                "Borrowed from Phoenix routers, Ecto schemas, Oban workers and OTP supervision trees. Not a framework you disappear into."
              )}
            </p>
            <p>
              <span class="t-faint" aria-hidden="true">// </span>{gettext(
                "No SQL here. GitHub keeps the content, Phoenix serves an ETS projection, and the agent asks before it writes."
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
              <span class="t-faint"> — {gettext("this site, open source")}</span>
            </p>
          </div>
        </div>
      </div>

      <div id="spectre-evolution" class="term-window overflow-hidden">
        <div class="term-bar">
          <span class="term-dots" aria-hidden="true">
            <span class="term-dot"></span>
            <span class="term-dot"></span>
            <span class="term-dot"></span>
          </span>
          <span class="term-title">$ spectre reflect --propose</span>
          <span class="ml-auto hidden flex-none t-faint sm:block">governed evolution</span>
        </div>
        <div class="term-body p-5 sm:p-7">
          <p class="term-prompt text-[0.72rem] t-faint">man spectre-morph</p>
          <h2 class="mt-3 text-xl font-bold tracking-tight t-strong sm:text-2xl">
            {gettext("How an agent can improve itself")}
          </h2>
          <p class="mt-4 max-w-4xl text-[0.8rem] leading-7 t-dim">
            {gettext(
              "Spectre %{version} can record explicitly enabled, redacted experience, inspect the active agent definition, and propose bounded changes to skills or configuration. The proposal is inert data: it cannot publish, approve, or activate itself.",
              version: spectre_version()
            )}
          </p>

          <ol class="mt-7 grid gap-px overflow-hidden border border-[color:var(--line)] bg-[color:var(--line)] sm:grid-cols-2 lg:grid-cols-4">
            <li
              :for={{step, index} <- Enum.with_index(@evolution_path, 1)}
              id={"spectre-evolution-step-#{index}"}
              class="bg-[color:var(--panel)] p-4"
            >
              <p class="term-prompt text-[0.66rem] t-faint">0{index} / {step.command}</p>
              <h3 class="mt-2 text-[0.76rem] font-bold t-strong">{step.title}</h3>
              <p class="mt-2 text-[0.7rem] leading-5 t-dim">{step.description}</p>
            </li>
          </ol>

          <p class="mt-6 border-l-2 border-[color:var(--line-strong)] pl-4 text-[0.78rem] leading-6 t-strong">
            {gettext(
              "Self-improving does not mean self-authorizing: evaluation, human review when required, activation, and rollback stay outside the model."
            )}
          </p>
        </div>
      </div>

      <div class="flex flex-wrap items-end justify-between gap-4 border-b border-[color:var(--line)] pb-4 pt-6">
        <div>
          <p class="term-prompt text-[0.72rem] t-faint">ls -1 spectre*</p>
          <h2 class="mt-3 text-xl font-bold tracking-tight t-strong sm:text-2xl">
            {gettext("One core, optional powers")}
          </h2>
        </div>
        <span class="term-chip">
          {ngettext("%{count} library", "%{count} libraries", length(@libraries))}
        </span>
      </div>

      <div
        id="spectre-capabilities-explainer"
        class="term-window border-l-2 border-l-[color:var(--line-strong)] p-5 sm:p-6"
      >
        <p class="term-prompt text-[0.72rem] t-faint">cat STACK.md</p>
        <p class="mt-3 max-w-4xl text-[0.82rem] leading-7 t-body">
          {gettext(
            "There is still one agent, one identity, and one lifecycle. The spectre_* packages below are focused libraries you can install as capabilities — memory, planning, browser perception, model choice, channels, or protocols. They do not spawn a cast of specialist agents."
          )}
        </p>
        <p class="mt-3 max-w-4xl text-[0.74rem] leading-6 t-dim">
          {gettext(
            "Installing a package only makes a capability available. A Flow, Work, Skill, or policy must still bind it explicitly, and the host keeps authorization and side effects."
          )}
        </p>
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
            <span class="ml-auto flex-none t-faint">
              {if(library.core?, do: gettext("foundation"), else: gettext("capability"))} · {library.role}
            </span>
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

      <div
        :if={@ecosystem}
        id="spectre-compatibility"
        class="term-window overflow-hidden"
      >
        <div class="term-bar">
          <span class="term-dots" aria-hidden="true">
            <span class="term-dot"></span>
            <span class="term-dot"></span>
            <span class="term-dot"></span>
          </span>
          <span class="term-title">$ spectre status --ecosystem</span>
          <span class="ml-auto hidden flex-none t-faint sm:block">
            {gettext("checked %{timestamp}", timestamp: checked_at(@ecosystem))}
          </span>
        </div>
        <div class="term-body p-5 sm:p-7">
          <p class="term-prompt text-[0.72rem] t-faint">curl -s spectre_ecosystem/status.json</p>
          <h2 class="mt-3 text-xl font-bold tracking-tight t-strong sm:text-2xl">
            {gettext("Compatibility with the current core")}
          </h2>
          <p class="mt-4 max-w-4xl text-[0.8rem] leading-7 t-dim">
            {gettext(
              "Every satellite library is rebuilt and tested against the commit that Spectre core is on today. The table is the published result of that run, not a promise: this page reads it once a day and shows exactly what came back."
            )}
          </p>

          <div class="mt-6 flex flex-wrap gap-2">
            <span class="term-chip">
              {ngettext(
                "%{count} library checked",
                "%{count} libraries checked",
                @ecosystem.summary.total
              )}
            </span>
            <span class="term-chip">
              <span class="t-ok" aria-hidden="true">●</span>
              {gettext("%{count} passing", count: @ecosystem.summary.passing)}
            </span>
            <span :if={@ecosystem.summary.failing > 0} class="term-chip">
              <span class="t-fail" aria-hidden="true">✕</span>
              {gettext("%{count} failing", count: @ecosystem.summary.failing)}
            </span>
          </div>

          <div class="mt-6 w-full overflow-x-auto">
            <table class="term-table">
              <caption class="sr-only">
                {gettext("Compatibility of each Spectre library with the current core")}
              </caption>
              <thead>
                <tr>
                  <th scope="col">{gettext("library")}</th>
                  <th scope="col">{gettext("check")}</th>
                  <th scope="col">{gettext("version")}</th>
                  <th scope="col">{gettext("source")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={library <- @ecosystem.libraries} id={"compat-#{library.name}"}>
                  <th scope="row" class="font-normal">
                    <a
                      :if={library.repository_url}
                      href={library.repository_url}
                      rel="noopener noreferrer"
                      class="t-strong underline decoration-dashed underline-offset-4 transition hover:t-invert"
                    >
                      {library.name}
                    </a>
                    <span :if={is_nil(library.repository_url)} class="t-strong">
                      {library.name}
                    </span>
                  </th>
                  <td>
                    <a
                      :if={library.run_url}
                      href={library.run_url}
                      rel="noopener noreferrer"
                      class={["transition hover:t-invert", status_tone(library.status)]}
                    >
                      <span aria-hidden="true">{status_glyph(library.status)}</span>
                      {status_label(library.status)}
                    </a>
                    <span :if={is_nil(library.run_url)} class={status_tone(library.status)}>
                      <span aria-hidden="true">{status_glyph(library.status)}</span>
                      {status_label(library.status)}
                    </span>
                  </td>
                  <td>
                    <a
                      :if={library.version && library.version_url}
                      href={library.version_url}
                      rel="noopener noreferrer"
                      class="transition hover:t-invert"
                    >
                      {library.version}
                    </a>
                    <span :if={library.version && is_nil(library.version_url)}>
                      {library.version}
                    </span>
                    <span :if={is_nil(library.version)} class="t-faint" aria-hidden="true">—</span>
                  </td>
                  <td class="t-dim">{source_label(library.source)}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <p class="mt-5 border-t border-dashed border-[color:var(--line)] pt-4 text-[0.7rem] leading-6 t-faint">
            <span aria-hidden="true">// </span>
            <a
              href={ecosystem_status_url()}
              rel="noopener noreferrer"
              class="t-dim transition hover:t-strong"
            >
              elchemista.github.io/spectre_ecosystem
            </a>
            <span> — {gettext("the full report, refreshed by its own scheduled run")}</span>
          </p>
        </div>
      </div>

      <p class="pt-2 text-[0.72rem] leading-6 t-faint">
        <span aria-hidden="true">// </span>{gettext("Also running under this site:")}
        <span :for={{tool, index} <- Enum.with_index(companion_tools())}>{if(index > 0, do: ", ")}<a
            href={"https://github.com/#{tool.repo}"}
            rel="noopener noreferrer"
            class="t-dim transition hover:t-strong"
          >{tool.name}</a></span>.
      </p>
    </section>
    """
  end

  # When the report was produced upstream. The fetch time is the fallback, so
  # the row never claims a publication moment the document did not carry.
  defp checked_at(%{generated_at: %DateTime{} = generated_at}), do: format_timestamp(generated_at)
  defp checked_at(%{fetched_at: %DateTime{} = fetched_at}), do: format_timestamp(fetched_at)

  # Both timestamps are already UTC: the parser only accepts what
  # `DateTime.from_iso8601/1` normalizes, and the fetch time is `utc_now/0`.
  defp format_timestamp(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  # Status is never carried by colour alone: each cell also states the outcome
  # in words and marks it with a glyph.
  defp status_tone(:passing), do: "t-ok"
  defp status_tone(:failing), do: "t-fail"
  defp status_tone(_status), do: "t-dim"

  defp status_glyph(:passing), do: "● "
  defp status_glyph(:failing), do: "✕ "
  defp status_glyph(_status), do: "○ "

  defp status_label(:passing), do: gettext("passing")
  defp status_label(:failing), do: gettext("failing")
  defp status_label(:pending), do: gettext("pending")
  defp status_label(:stale), do: gettext("stale")
  defp status_label(:not_configured), do: gettext("not configured")
  defp status_label(:not_run), do: gettext("not run")
  defp status_label(_status), do: gettext("unknown")

  defp source_label(:hex), do: "hex"
  defp source_label(:github), do: "github"
  defp source_label(_source), do: gettext("unknown")

  # Verbatim from the "safety boundary" section of deps/spectre/README.md.
  defp safety_boundary do
    [
      gettext("models and routes may propose work"),
      gettext("protected work must pass a deterministic policy"),
      gettext("approval changes state but does not execute the work"),
      gettext("execution happens only through an explicit host call"),
      gettext("every terminal outcome is returned as data")
    ]
  end

  # Trimmed from the support agent in deps/spectre/README.md.
  defp dsl_example do
    ~S"""
    defmodule MyApp.SupportAgent do
      use Spectre.Agent

      model(MyApp.LLM, purpose: :smart)
      router(via: [:regex, :embedding, :llm_classifier])

      actions MyApp.SupportActions do
        protect(:delete_account, with: :delete_account_confirmation)
      end

      policy :delete_account_confirmation do
        request(:confirm_delete_account)
        accept(:confirmed_delete, regex: ~r/^yes, delete it$/i)
        reject(:cancel_delete, regex: ~r/^(no|cancel)$/i)
        attempts(3, then: :cancel_pending)
      end

      interrupt :HELP, regex: ~r/^(help|menu)$/i do
        reply(:help)
      end
    end
    """
  end

  defp request_path do
    [
      %{node: "one blog agent", note: gettext("one identity · one lifecycle")},
      %{node: "├── spectre_beam", note: gettext("channel capability")},
      %{node: "├── spectre_prism", note: gettext("model-selection capability")},
      %{node: "├── spectre_kinetic", note: gettext("planning capability")},
      %{node: "├── spectre_lens", note: gettext("browser capability")},
      %{node: "├── skills", note: gettext("reader · editorial · operations")},
      %{node: "└── spectre core", note: gettext("routing · state · policy · effects")},
      %{node: "    └── writer → git → ets", note: gettext("the page you are reading")}
    ]
  end

  defp evolution_path do
    [
      %{
        command: "observe",
        title: gettext("Experience"),
        description:
          gettext("The host opts in and records bounded evidence with sensitive values redacted.")
      },
      %{
        command: "reflect",
        title: gettext("Reflection"),
        description:
          gettext("Spectre compares what was declared, what is active, and what was observed.")
      },
      %{
        command: "propose",
        title: gettext("Proposal"),
        description:
          gettext(
            "Forge may suggest a closed change, but that proposal has no authority of its own."
          )
      },
      %{
        command: "govern",
        title: gettext("Evaluation and activation"),
        description:
          gettext(
            "Protected tests, review, approval, activation, and rollback guard every change."
          )
      }
    ]
  end

  # Taglines follow each repository's own GitHub description.
  defp libraries do
    [
      %{
        name: "spectre",
        repo: "elchemista/spectre",
        role: "runtime",
        core?: true,
        tagline:
          gettext(
            "The OTP-native core: one owner for state, explicit lifecycle and governance. Every optional power plugs into this foundation."
          )
      },
      %{
        name: "spectre_mnemonic",
        repo: "elchemista/spectre_mnemonic",
        role: "memory",
        core?: false,
        tagline:
          gettext(
            "Semantic memory engine: ETS working memory, durable recall, typed observations and mental models."
          )
      },
      %{
        name: "spectre_ledger",
        repo: "elchemista/spectre_ledger",
        role: "checkpoints",
        core?: false,
        tagline:
          gettext(
            "Append-only durable checkpoints for Spectre agents, so state survives a crash."
          )
      },
      %{
        name: "spectre_kinetic",
        repo: "elchemista/spectre_kinetic",
        role: "planning",
        core?: false,
        tagline:
          gettext(
            "Elixir-first planning toolkit: Action Language in, validated tool calls out. No JSON schema in the prompt."
          )
      },
      %{
        name: "spectre_pulse",
        repo: "elchemista/spectre_pulse",
        role: "protocol",
        core?: false,
        tagline: gettext("Transport-independent protocol for agents talking to other agents.")
      },
      %{
        name: "spectre_directive",
        repo: "elchemista/spectre_directive",
        role: "missions",
        core?: false,
        tagline: gettext("An embeddable mission loop for Elixir agents.")
      },
      %{
        name: "spectre_lens",
        repo: "elchemista/spectre_lens",
        role: "browser",
        core?: false,
        tagline:
          gettext(
            "Agent-first browser lens for Lightpanda, so an agent can read what it shipped."
          )
      },
      %{
        name: "spectre_prism",
        repo: "elchemista/spectre_prism",
        role: "models",
        core?: false,
        tagline:
          gettext(
            "Picks the model per request across OpenAI, OpenRouter, Ollama and Gemini, enforcing privacy, context, cost and latency limits before the call."
          )
      },
      %{
        name: "spectre_beam",
        repo: "elchemista/spectre_beam",
        role: "channels",
        core?: false,
        tagline:
          gettext(
            "The external-channel boundary: it normalizes provider events and delivers messages idempotently."
          )
      },
      %{
        name: "spectre_lab",
        repo: "elchemista/spectre_lab",
        role: "debugging",
        core?: false,
        tagline:
          gettext(
            "Debug Spectre agents with checkpoint playback and isolated testing tools, away from production."
          )
      }
    ]
  end

  defp companion_tools do
    [
      %{name: "vettore", repo: "elchemista/vettore"},
      %{name: "ex_fastembed", repo: "elchemista/ex_fastembed"},
      %{name: "ex_gram", repo: "elchemista/ex_gram"}
    ]
  end
end
