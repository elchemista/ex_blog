defmodule ExBlogWeb.Showcase do
  @moduledoc """
  Homepage presentation of the released Spectre 0.4 AgentServer architecture.

  Examples follow the tagged core guides: Stack, Agent and Server, registered
  effects and the trusted consumer's consent protocol. Model adapters are
  application-owned; the optional Kinetic mail catalog deliberately simulates
  delivery. ExBlog's retained editorial integration is identified separately.
  Compatibility rows come from the published ecosystem report.
  """

  use Phoenix.Component
  use Gettext, backend: ExBlogWeb.Gettext

  @spectre_repo "elchemista/spectre"
  @blog_repo "elchemista/ex_blog"
  # The released version this page describes. Keep it here only: the chip, the
  # documentation link and the governed-execution paragraph all read it, so a
  # release bump is a one-line change.
  @spectre_version "0.4.0"
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
  The showcase: AgentServer architecture, executable API examples, governed
  consequences, optional libraries and the published compatibility report.
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
      |> assign(:effect_example, effect_example())
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
              "Build agents around supervised OTP processes, explicit state and application callbacks. Stack installs capabilities, Agent recognizes intent, and Server owns the conversation. GAM (Governed Act Model) checks authority before governed operations execute and records their observed outcomes."
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
                  "A model prepares a candidate; configured authority and required human consent determine whether GAM admits it."
                )}
              </p>
            </div>
            <div
              id="spectre-philosophy-routing"
              class="border-l border-[color:var(--line-strong)] pl-4"
            >
              <p class="text-[0.72rem] font-bold t-strong">
                {gettext("Routing combines evidence")}
              </p>
              <p class="mt-2 text-[0.72rem] leading-5 t-dim">
                {gettext(
                  "Combine regex, reviewed examples, vector similarity and classifier models; Server callbacks own what happens next."
                )}
              </p>
            </div>
            <div id="spectre-philosophy-data" class="border-l border-[color:var(--line-strong)] pl-4">
              <p class="text-[0.72rem] font-bold t-strong">
                {gettext("Skills keep independent state")}
              </p>
              <p class="mt-2 text-[0.72rem] leading-5 t-dim">
                {gettext(
                  "Mounted Skills have separate Server processes and checkpoints while sharing their root agent’s GAM Domain and mount restrictions."
                )}
              </p>
            </div>
          </div>

          <p class="term-prompt mt-8 text-[0.72rem] t-faint">cat GAM.md</p>
          <p class="mt-3 text-[0.78rem] t-dim">
            {gettext("From a proposed consequence to a recorded outcome:")}
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
          <span class="term-title">stack_agent_server.ex</span>
          <span class="ml-auto flex-none t-faint">elixir</span>
        </div>
        <div class="term-body p-5 sm:p-7">
          <p class="text-[0.78rem] leading-6 t-dim">
            <span class="t-faint" aria-hidden="true">// </span>{gettext(
              "Stack → Agent → Server: install capabilities, combine regex, embeddings and model classification, then handle the selected intent in ordinary callbacks. MyApp.Embeddings and MyApp.IntentModel are application-supplied providers; the mail example requires optional spectre_kinetic."
            )}
          </p>
          <pre id="spectre-agent-server-example" class="term-code mt-5" data-language="elixir"><code>{@dsl_example}</code></pre>
          <p class="mt-6 text-[0.78rem] leading-6 t-dim">
            {gettext(
              "Define the typed action catalog before compiling the Stack. This fixture simulates delivery; replace its implementation with your mail transport. The configured consumer renders the exact request and submits the human’s separate choice."
            )}
          </p>
          <pre id="spectre-governed-example" class="term-code mt-5" data-language="elixir"><code>{@effect_example}</code></pre>
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
            <span class="term-title">request_lifecycle.txt</span>
          </div>
          <div class="term-body">
            <p class="text-[0.78rem] leading-6 t-dim">
              <span class="t-faint" aria-hidden="true">// </span>{gettext(
                "How a governed request moves from recognition to an observed result."
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
                "Use models where they help: semantic recognition, classification and generation. Keep application state, tool execution and authority explicit."
              )}
            </p>
            <p>
              <span class="t-faint" aria-hidden="true">// </span>{gettext(
                "Ordinary Elixir callbacks, supervised workers and named continuations keep business behavior readable and testable."
              )}
            </p>
            <p>
              <span class="t-faint" aria-hidden="true">// </span>{gettext(
                "ExBlog keeps its editorial integration on Spectre 0.4's retained compatibility APIs. The example above shows AgentServer for new applications."
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
          <span class="term-title">governed_execution.txt</span>
          <span class="ml-auto hidden flex-none t-faint sm:block">governed execution</span>
        </div>
        <div class="term-body p-5 sm:p-7">
          <p class="term-prompt text-[0.72rem] t-faint">cat GAM.md</p>
          <h2 class="mt-3 text-xl font-bold tracking-tight t-strong sm:text-2xl">
            {gettext("From intent to authorized execution")}
          </h2>
          <p class="mt-4 max-w-4xl text-[0.8rem] leading-7 t-dim">
            {gettext(
              "Spectre %{version} routes requests to Server callbacks, runs models and tools in workers, and admits configured operations through GAM. Required human consent binds the exact presentation; the execution outcome remains a separate recorded fact.",
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
              "An approval authorizes the presented operation; only an observed successful Outcome establishes that it completed."
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
            "Start with the core and install only the capabilities your application needs: memory, planning, browser access, model selection, channels, storage or agent messaging. Mounted Skills can run independently while sharing the root agent’s GAM Domain."
          )}
        </p>
        <p class="mt-3 max-w-4xl text-[0.74rem] leading-6 t-dim">
          {gettext(
            "Installing a package exposes tools and resources. The Server queues work; registered effect adapters and configured GAM operations define the governed execution path."
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
            {gettext("Compatibility with the tested core")}
          </h2>
          <p class="mt-4 max-w-4xl text-[0.8rem] leading-7 t-dim">
            {gettext(
              "Each report records the core and satellite revisions it tested. This page displays the published results and their timestamp; a passing row describes that tested combination."
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
                {gettext("Compatibility of each Spectre library with the tested core")}
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
        <span aria-hidden="true">// </span>{gettext("Related tools:")}
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

  defp safety_boundary do
    [
      gettext("declare and register the concrete operation"),
      gettext("check the caller’s configured authority"),
      gettext("show the exact consequence and collect required human consent"),
      gettext("execute only after GAM admission"),
      gettext("record the observed result, including uncertainty")
    ]
  end

  # Providers are application-owned; the separately shown mail catalog is a fixture.
  defp dsl_example do
    ~S"""
    # 1. Stack: optional Kinetic registers the typed mail tool and effect.
    defmodule MyApp.AI do
      use Spectre.Stack
      install Spectre.Kinetic, mode: :closed_moves,
        actions: MyApp.MailActions, modes: [send_email: :write]
    end

    # 2. Agent: recognize intent with patterns, similarity or a model.
    defmodule MyApp.SupportAgent do
      use Spectre.Agent, stack: MyApp.AI, server: MyApp.SupportServer
      embedding MyApp.Embeddings
      classifier :llm, MyApp.IntentModel
      router strategies: [:regex, :embedding, :llm_classifier]

      flow :support do
        on :pricing, regex: ~r/\b(price|pricing)\b/i,
          semantic_examples: ["How much does a subscription cost?"]
        on :send_email, regex: ~r/^send email$/i,
          semantic_examples: ["Send the prepared message"]
      end
    end

    # 3. Server: return responses or concrete governed proposals.
    defmodule MyApp.SupportServer do
      use Spectre.Server, tools: MyApp.AI

      @impl true
      def handle_flow({:support, :pricing}, _input, ctx),
        do: respond(ctx, "Plans start at EUR 20 per month.")

      def handle_flow({:support, :send_email}, _input, ctx),
        do: propose(ctx, {:kinetic, :send_email},
          %{"to" => "team@example.com", "body" => "The report is ready."},
          on_result: :sent)

      def handle_flow(:unmatched, _input, ctx),
        do: respond(ctx, "Ask about pricing or send the prepared email.")

      @impl true
      def handle_result(:sent, {:governed, %{outcome: %{status: :succeeded}}}, ctx),
        do: respond(ctx, "The registered mail operation completed.")

      def handle_result(tag, result, ctx), do: super(tag, result, ctx)
    end

    {:ok, server} = Spectre.Server.start_link(
      agent: MyApp.SupportAgent, consumer: self(),
      identity: %{subject: "customer-42"},
      gam: [operations: %{{:kinetic, :send_email} => [confirm: true]}])

    {:ok, interaction} = Spectre.Server.input(server, "What is the price?")
    receive do
      {Spectre.Server, ^server, {:response, ^interaction, text, _meta}} ->
        IO.puts(text)
    after
      5_000 -> raise "No response"
    end
    """
  end

  defp effect_example do
    ~S"""
    # Host-owned catalog; define before compiling MyApp.AI.
    # This function simulates delivery and sends no real email.
    defmodule MyApp.MailActions do
      use SpectreKinetic
      @al ~s(SEND EMAIL TO="team@example.com" BODY="The report is ready.")
      @doc "Simulate delivery; replace with the application's mail transport."
      @spec send_email(String.t(), String.t()) :: {:ok, map()}
      def send_email(to, body), do: {:ok, %{to: to, body: body, simulated: true}}
    end

    # Continue in the configured consumer, using server from the first example.
    {:ok, email_interaction} = Spectre.Server.input(server, "send email")
    receive do
      {Spectre.Server.GAM.Managed, _owner, {:presentation, material}} ->
        IO.puts(material["rendered_payload"])
        ref = material["presentation_ref"]
        :ok = Spectre.Server.presented(server, ref)
        receive do
          {Spectre.Server, ^server, {:pending, ^email_interaction, _id}} -> :ok
        after
          5_000 -> raise "Consent wait unavailable"
        end
        choice = if IO.gets("Confirm? Type yes: ") == "yes\n", do: :confirm, else: :reject
        Spectre.Server.decide(server, nil, ref, choice)
    after
      5_000 -> raise "No presentation"
    end
    """
  end

  defp request_path do
    [
      %{node: "Stack", note: gettext("installed tools and supervised resources")},
      %{node: "└── Agent router", note: gettext("patterns · vectors · classifier models")},
      %{node: "    └── Server callbacks", note: gettext("conversation state and continuations")},
      %{node: "        ├── workers", note: gettext("models and cognitive tools")},
      %{
        node: "        └── Managed GAM",
        note: gettext("configured authority and required consent")
      },
      %{
        node: "            ├── Presentation",
        note: gettext("exact consequence shown to the human")
      },
      %{
        node: "            └── Act → executor → Outcome",
        note: gettext("admission and observed execution remain distinct")
      }
    ]
  end

  defp evolution_path do
    [
      %{
        command: "recognize",
        title: gettext("Recognize intent"),
        description: gettext("Combine route evidence and select a declared Server handler.")
      },
      %{
        command: "propose",
        title: gettext("Prepare the operation"),
        description: gettext("Freeze the concrete arguments and registered execution contract.")
      },
      %{
        command: "admit",
        title: gettext("Verify authority and consent"),
        description:
          gettext("GAM checks the mandate and any required human approval before execution.")
      },
      %{
        command: "observe",
        title: gettext("Record the outcome"),
        description:
          gettext(
            "Keep success, refusal and uncertain external results separate; reconcile before retrying."
          )
      }
    ]
  end

  # Summaries describe the verified Spectre 0.4 installation and helper contracts.
  defp libraries do
    [
      %{
        name: "spectre",
        repo: "elchemista/spectre",
        role: "runtime",
        core?: true,
        tagline:
          gettext(
            "The OTP core for AgentServer conversations, workers, routing and GAM authority. Runs in RAM without any satellite package."
          )
      },
      %{
        name: "spectre_mnemonic",
        repo: "elchemista/spectre_mnemonic",
        role: "memory",
        core?: false,
        tagline:
          gettext(
            "Explicit memory search, recall and writes in authenticated application partitions."
          )
      },
      %{
        name: "spectre_ledger",
        repo: "elchemista/spectre_ledger",
        role: "storage",
        core?: false,
        tagline:
          gettext(
            "Persist Server checkpoints, coordination and canonical GAM history, with file and PostgreSQL backends."
          )
      },
      %{
        name: "spectre_kinetic",
        repo: "elchemista/spectre_kinetic",
        role: "actions",
        core?: false,
        tagline:
          gettext(
            "Interpret consolidated model output into validated action proposals; admitted operations reach the registered executor."
          )
      },
      %{
        name: "spectre_pulse",
        repo: "elchemista/spectre_pulse",
        role: "protocol",
        core?: false,
        tagline:
          gettext(
            "Authenticated agent messaging across transports; delivery receipts never stand in for human consent."
          )
      },
      %{
        name: "spectre_directive",
        repo: "elchemista/spectre_directive",
        role: "missions",
        core?: false,
        tagline:
          gettext(
            "Pure resumable mission reducers that return requests for the Server to handle."
          )
      },
      %{
        name: "spectre_lens",
        repo: "elchemista/spectre_lens",
        role: "browser",
        core?: false,
        tagline:
          gettext(
            "Navigate, inspect and act through supervised browser resources with explicit governed bindings."
          )
      },
      %{
        name: "spectre_prism",
        repo: "elchemista/spectre_prism",
        role: "models",
        core?: false,
        tagline:
          gettext(
            "Select model profiles for generation, classification and embeddings using host-defined providers and constraints."
          )
      },
      %{
        name: "spectre_beam",
        repo: "elchemista/spectre_beam",
        role: "channels",
        core?: false,
        tagline:
          gettext(
            "Normalize channel input and deliver through configured adapters; bind consequential sends to GAM."
          )
      },
      %{
        name: "spectre_lab",
        repo: "elchemista/spectre_lab",
        role: "debugging",
        core?: false,
        tagline:
          gettext(
            "Inspect bounded Server diagnostics and checkpoint metadata, with separate offline archive tools."
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
