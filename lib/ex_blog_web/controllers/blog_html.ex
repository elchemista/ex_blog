defmodule ExBlogWeb.BlogHTML do
  @moduledoc false

  use ExBlogWeb, :html

  import ExBlogWeb.Showcase

  embed_templates "blog_html/*"

  attr :article, ExBlog.Content.Article, required: true
  attr :featured, :boolean, default: false

  def article_card(assigns) do
    ~H"""
    <article
      id={"article-card-#{@article.lang}-#{@article.slug}"}
      class="term-window term-window--link group relative overflow-hidden"
    >
      <div class="term-bar">
        <span class="term-dots" aria-hidden="true">
          <span class="term-dot"></span>
          <span class="term-dot"></span>
          <span class="term-dot"></span>
        </span>
        <span class="term-title">{file_path(@article)}</span>
        <span class="ml-auto flex flex-none items-center gap-2 t-faint">
          <span :if={@featured} class="hidden sm:inline">◆ {gettext("pinned")}</span>
          <time datetime={date_string(@article.date)}>{format_date(@article.date)}</time>
        </span>
      </div>

      <div class={["md:grid", @featured && "md:grid-cols-[1.25fr_0.75fr]"]}>
        <div class={["term-body", @featured && "sm:p-8"]}>
          <p class="term-prompt text-[0.72rem] t-dim">
            cat {file_path(@article)}
          </p>

          <h2 class={[
            "mt-4 font-bold leading-tight tracking-tight t-strong",
            if(@featured, do: "text-2xl sm:text-4xl", else: "text-xl sm:text-2xl")
          ]}>
            <.link
              href={~p"/#{@article.lang}/#{@article.slug}"}
              class="after:absolute after:inset-0 group-hover:underline group-hover:decoration-dashed group-hover:underline-offset-8"
            >
              {@article.title}
            </.link>
          </h2>

          <p class={[
            "mt-4 text-[0.85rem] leading-7 t-dim",
            if(@featured, do: "line-clamp-4 sm:text-[0.9rem]", else: "line-clamp-3")
          ]}>
            <span class="t-faint" aria-hidden="true">// </span>{@article.excerpt}
          </p>

          <div class="mt-6 flex flex-wrap items-center gap-x-4 gap-y-2 border-t border-dashed border-[color:var(--line)] pt-4 text-[0.7rem] t-faint">
            <span :if={@article.category} class="t-dim">#{@article.category}</span>
            <span aria-hidden="true">·</span>
            <span>{gettext("%{count} min", count: reading_time(@article.body))}</span>
            <span aria-hidden="true">·</span>
            <span>{@article.lang}</span>
            <span class="ml-auto flex items-center gap-1.5 t-strong">
              {gettext("open")}
              <span class="transition-transform group-hover:translate-x-1" aria-hidden="true">→</span>
            </span>
          </div>
        </div>

        <div
          :if={@featured}
          class="hidden border-l border-[color:var(--line)] bg-[color:var(--surface-bar)] p-8 md:flex md:flex-col md:justify-between"
          aria-hidden="true"
        >
          <div class="text-[0.8rem] leading-[1.1] tracking-[0.12em] t-faint">
            <div>░░░░░░░░▒▒▒▒▒▓▓▓</div>
            <div>░░░░░░▒▒▒▒▒▓▓▓██</div>
            <div>░░░░▒▒▒▒▓▓▓█████</div>
            <div>░░▒▒▒▓▓▓████████</div>
            <div>▒▒▒▓▓▓██████████</div>
            <div>▒▓▓▓████████████</div>
          </div>
          <dl class="mt-8 space-y-1.5 border-t border-dashed border-[color:var(--line)] pt-5 text-[0.68rem] leading-5">
            <div class="flex gap-3">
              <dt class="w-16 shrink-0 t-faint">branch</dt>
              <dd class="t-dim">master</dd>
            </div>
            <div class="flex gap-3">
              <dt class="w-16 shrink-0 t-faint">slug</dt>
              <dd class="truncate t-dim">{@article.slug}</dd>
            </div>
            <div class="flex gap-3">
              <dt class="w-16 shrink-0 t-faint">words</dt>
              <dd class="t-dim">{word_count(@article.body)}</dd>
            </div>
            <div class="flex gap-3">
              <dt class="w-16 shrink-0 t-faint">status</dt>
              <dd class="t-strong">{gettext("published")}</dd>
            </div>
          </dl>
        </div>
      </div>
    </article>
    """
  end

  def file_path(article), do: "posts/#{article.lang}/#{article.slug}.md"

  def word_count(body) when is_binary(body) do
    body |> String.split(~r/\s+/u, trim: true) |> length()
  end

  def word_count(_body), do: 0

  @doc "Wraps a translated fragment in the inverted highlight block."
  def highlight(text) do
    escaped = text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    ~s(<span class="t-invert px-2">#{escaped}</span>)
  end

  def format_date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")
  def format_date(_date), do: gettext("no date")
  def date_string(%Date{} = date), do: Date.to_iso8601(date)
  def date_string(_date), do: nil

  def reading_time(body) when is_binary(body) do
    body
    |> String.split(~r/\s+/u, trim: true)
    |> length()
    |> Kernel./(200)
    |> Float.ceil()
    |> trunc()
    |> max(1)
  end

  def cover_source(nil), do: nil

  def cover_source("/" <> rest = path) do
    segments = String.split(rest, "/", trim: true)

    if rest != "" and not String.starts_with?(rest, "/") and
         not String.contains?(rest, ["\\", "\0"]) and
         Enum.all?(segments, &(&1 not in [".", ".."])) do
      path
    end
  end

  def cover_source(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> url
      _invalid -> nil
    end
  end

  def cover_source(_cover), do: nil

  def cover_alt(article) do
    article.cover_alt || gettext("Cover image for %{title}", title: article.title)
  end
end
