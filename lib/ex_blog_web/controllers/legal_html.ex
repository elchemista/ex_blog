defmodule ExBlogWeb.LegalHTML do
  @moduledoc false

  use ExBlogWeb, :html

  embed_templates "legal_html/*"

  attr :policy, :map, required: true
  attr :site_name, :string, required: true
  attr :site_domain, :string, required: true
  attr :contact_email, :string, required: true
  attr :current_language, :string, required: true

  def policy_document(assigns) do
    ~H"""
    <section
      id={@policy.id}
      data-site-domain={@site_domain}
      data-policy-language={@current_language}
      class={["mx-auto w-full max-w-6xl px-4 pb-20 pt-8 sm:px-6 lg:px-8"]}
    >
      <nav
        id="legal-breadcrumbs"
        aria-label="Breadcrumb"
        class={["flex flex-wrap items-center gap-1.5 text-[0.72rem] t-faint"]}
      >
        <span aria-hidden="true">$ cd</span>
        <.link href={~p"/#{@current_language}"} class={["transition hover:t-strong"]}>
          ~/{@current_language}
        </.link>
        <span aria-hidden="true">/</span>
        <span aria-current="page" class={["t-dim"]}>legal</span>
      </nav>

      <header class={["term-window mt-4 overflow-hidden"]}>
        <div class={["term-bar"]}>
          <span class={["term-dots"]} aria-hidden="true">
            <span class={["term-dot"]}></span>
            <span class={["term-dot"]}></span>
            <span class={["term-dot"]}></span>
          </span>
          <span class={["term-title"]}>{@policy.file}</span>
          <span class={["ml-auto hidden t-faint sm:block"]}>read-only</span>
        </div>

        <div class={["term-body p-5 sm:p-9"]}>
          <p class={["term-prompt text-[0.72rem] uppercase tracking-[0.14em] t-faint"]}>
            {@policy.eyebrow}
          </p>
          <h1
            id="legal-title"
            class={[
              "mt-4 max-w-4xl text-3xl font-bold leading-tight tracking-tight text-balance t-strong sm:text-5xl"
            ]}
          >
            {@policy.title}
          </h1>
          <p class={["mt-5 max-w-3xl text-[0.85rem] leading-7 t-dim sm:text-[0.92rem]"]}>
            <span class={["t-faint"]} aria-hidden="true">// </span>{@policy.summary}
          </p>
          <dl class={[
            "mt-7 grid gap-3 border-t border-dashed border-[color:var(--line)] pt-5 text-[0.7rem] sm:grid-cols-3"
          ]}>
            <div>
              <dt class={["t-faint"]}>host</dt>
              <dd class={["mt-1 t-strong"]}>{@site_domain}</dd>
            </div>
            <div>
              <dt class={["t-faint"]}>language</dt>
              <dd class={["mt-1 t-strong"]}>{@current_language}</dd>
            </div>
            <div>
              <dt class={["t-faint"]}>last_updated</dt>
              <dd class={["mt-1 t-strong"]}>{@policy.updated}</dd>
            </div>
          </dl>
        </div>
      </header>

      <div class={["mt-8 grid items-start gap-8 lg:grid-cols-[14rem_minmax(0,1fr)]"]}>
        <aside id="legal-toc" class={["term-window overflow-hidden lg:sticky lg:top-20"]}>
          <div class={["term-bar"]}>
            <span class={["term-title"]}>index</span>
          </div>
          <nav aria-label="Indice dell'informativa" class={["p-4"]}>
            <ol class={["space-y-2 text-[0.72rem]"]}>
              <li :for={section <- @policy.sections}>
                <a
                  href={"##{section.id}"}
                  class={[
                    "block border-l border-[color:var(--line)] py-1 pl-3 leading-5 t-faint transition hover:border-[color:var(--line-strong)] hover:t-strong"
                  ]}
                >
                  {section.title}
                </a>
              </li>
            </ol>
          </nav>
        </aside>

        <article id="legal-content" class={["space-y-6"]}>
          <section
            :for={section <- @policy.sections}
            id={section.id}
            class={["term-window scroll-mt-24 overflow-hidden"]}
          >
            <div class={["term-bar"]}>
              <span class={["term-title"]}>{section.id}.md</span>
            </div>
            <div class={["term-body p-5 sm:p-7"]}>
              <h2 class={["text-xl font-bold tracking-tight t-strong sm:text-2xl"]}>
                {section.title}
              </h2>
              <div class={["mt-4 space-y-4 text-[0.84rem] leading-7 t-dim sm:text-[0.9rem]"]}>
                <p :for={paragraph <- section.paragraphs}>{paragraph}</p>
              </div>
              <ul :if={section.items != []} class={["mt-5 space-y-3"]}>
                <li
                  :for={item <- section.items}
                  class={[
                    "border-l border-dashed border-[color:var(--line-strong)] pl-4 text-[0.82rem] leading-6 t-dim"
                  ]}
                >
                  <strong class={["t-strong"]}>{item.title}:</strong> {item.body}
                </li>
              </ul>
              <ul :if={section.links != []} class={["mt-5 flex flex-col items-start gap-2"]}>
                <li :for={link <- section.links}>
                  <a
                    href={link.href}
                    target="_blank"
                    rel="noopener noreferrer"
                    class={[
                      "text-[0.76rem] t-dim underline decoration-dashed underline-offset-4 transition hover:t-strong"
                    ]}
                  >
                    {link.label} <span aria-hidden="true">↗</span>
                  </a>
                </li>
              </ul>
            </div>
          </section>

          <section id="legal-contact" class={["term-window overflow-hidden"]}>
            <div class={["term-bar"]}>
              <span class={["term-title"]}>contact.env</span>
            </div>
            <div class={["term-body p-5 sm:p-7"]}>
              <p class={["term-prompt text-[0.76rem] t-dim"]}>cat DATA_CONTROLLER</p>
              <h2 class={["mt-4 text-xl font-bold tracking-tight t-strong"]}>
                {if(@current_language == "it", do: "Contatti", else: "Contact")}
              </h2>
              <dl class={["mt-5 grid gap-4 text-[0.8rem] sm:grid-cols-2"]}>
                <div>
                  <dt class={["t-faint"]}>controller</dt>
                  <dd id="legal-controller-name" class={["mt-1 t-strong"]}>{@site_name}</dd>
                </div>
                <div>
                  <dt class={["t-faint"]}>domain</dt>
                  <dd id="legal-domain" class={["mt-1 t-strong"]}>{@site_domain}</dd>
                </div>
                <div class={["sm:col-span-2"]}>
                  <dt class={["t-faint"]}>email</dt>
                  <dd class={["mt-1"]}>
                    <a
                      id="legal-contact-email"
                      href={"mailto:#{@contact_email}"}
                      class={[
                        "t-strong underline decoration-dashed underline-offset-4 transition hover:t-dim"
                      ]}
                    >
                      {@contact_email}
                    </a>
                  </dd>
                </div>
              </dl>
            </div>
          </section>

          <div
            id="related-legal-policy"
            class={[
              "flex flex-wrap items-center justify-between gap-4 border-t border-dashed border-[color:var(--line)] pt-6 text-[0.76rem]"
            ]}
          >
            <p class={["term-prompt t-faint"]}>
              {if(@current_language == "it", do: "leggi anche", else: "read next")}
            </p>
            <.link
              :if={@policy.kind == :cookie}
              href={~p"/#{@current_language}/privacy-policy"}
              class={["term-btn"]}
            >
              Privacy & GDPR <span aria-hidden="true">→</span>
            </.link>
            <.link
              :if={@policy.kind == :privacy}
              href={~p"/#{@current_language}/cookies-policy"}
              class={["term-btn"]}
            >
              Cookie Policy <span aria-hidden="true">→</span>
            </.link>
          </div>
        </article>
      </div>
    </section>
    """
  end
end
