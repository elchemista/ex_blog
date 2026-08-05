defmodule ExBlogWeb.Showcase do
  @moduledoc """
  Home page sections presenting the Spectre ecosystem.

  Every claim rendered here is sourced, not invented:

    * the definition, the safety boundary and the DSL example come from
      `deps/spectre/README.md`;
    * each library summary comes from its own GitHub description
      (`api.github.com/users/elchemista/repos`, checked 2026-08-04);
    * the request path comes from `docs/spectre-editorial-showcase.md`.

  Every `repo` below was verified to resolve on github.com. Re-check before
  adding one: a card links straight to it, so a private or renamed repository
  sends visitors to a 404.
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
  The whole showcase: what Spectre is, a DSL sample, the request path this site
  follows, the rationale, and the library catalog.
  """
  def spectre_showcase(assigns) do
    assigns =
      assigns
      |> assign(:libraries, libraries())
      |> assign(:dsl_example, dsl_example())

    ~H"""
    <section id="spectre-showcase" class="mt-16 space-y-6">
      <div class="flex flex-wrap items-end justify-between gap-4 border-b border-[color:var(--line)] pb-4">
        <div>
          <p class="term-prompt text-[0.72rem] t-faint">man spectre</p>
          <h2 class="mt-3 text-xl font-bold tracking-tight t-strong sm:text-2xl">
            {gettext("What Spectre is")}
          </h2>
        </div>
        <a href={spectre_repo_url()} rel="noopener noreferrer" class="term-chip">
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
          <span class="ml-auto hidden flex-none t-faint sm:block">S.P.E.C.T.R.E</span>
        </div>
        <div class="term-body p-5 sm:p-7">
          <p class="text-[0.85rem] leading-7 t-body sm:text-[0.9rem]">
            {gettext(
              "An agent is a supervised system, not a prompt. Spectre gives it one owner per piece of state, explicit messages at every boundary, and recovery planned from the start — the way OTP treats everything else."
            )}
          </p>

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

      <div class="flex flex-wrap items-end justify-between gap-4 border-b border-[color:var(--line)] pb-4 pt-6">
        <div>
          <p class="term-prompt text-[0.72rem] t-faint">ls -1 spectre*</p>
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

  # Taglines follow each repository's own GitHub description.
  defp libraries do
    [
      %{
        name: "spectre",
        repo: "elchemista/spectre",
        role: "runtime",
        tagline:
          gettext(
            "Supervised Process Event Controller for Transition and Reasoning with Elixir. The runtime the rest plugs into."
          )
      },
      %{
        name: "spectre_mnemonic",
        repo: "elchemista/spectre_mnemonic",
        role: "memory",
        tagline:
          gettext(
            "Semantic memory engine: ETS working memory, durable recall, typed observations and mental models."
          )
      },
      %{
        name: "spectre_kinetic",
        repo: "elchemista/spectre_kinetic",
        role: "planning",
        tagline:
          gettext(
            "Elixir-first planning toolkit: Action Language in, validated tool calls out. No JSON schema in the prompt."
          )
      },
      %{
        name: "spectre_pulse",
        repo: "elchemista/spectre_pulse",
        role: "protocol",
        tagline: gettext("Transport-independent protocol for agents talking to other agents.")
      },
      %{
        name: "spectre_directive",
        repo: "elchemista/spectre_directive",
        role: "missions",
        tagline: gettext("An embeddable mission loop for Elixir agents.")
      },
      %{
        name: "spectre_lens",
        repo: "elchemista/spectre_lens",
        role: "browser",
        tagline:
          gettext(
            "Agent-first browser lens for Lightpanda, so an agent can read what it shipped."
          )
      },
      %{
        name: "spectre_prism",
        repo: "elchemista/spectre_prism",
        role: "models",
        tagline:
          gettext(
            "Picks the model per request across OpenAI, OpenRouter, Ollama and Gemini, enforcing privacy, context, cost and latency limits before the call."
          )
      },
      %{
        name: "spectre_beam",
        repo: "elchemista/spectre_beam",
        role: "channels",
        tagline:
          gettext(
            "The external-channel boundary: it normalizes provider events and delivers messages idempotently."
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
