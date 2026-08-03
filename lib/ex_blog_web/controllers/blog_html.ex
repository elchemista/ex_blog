defmodule ExBlogWeb.BlogHTML do
  @moduledoc false

  use ExBlogWeb, :html

  embed_templates "blog_html/*"

  attr :article, ExBlog.Content.Article, required: true
  attr :featured, :boolean, default: false

  def article_card(assigns) do
    ~H"""
    <article
      id={"article-card-#{@article.lang}-#{@article.slug}"}
      class={[
        "group relative overflow-hidden rounded-[2rem] border border-stone-200/80 bg-white/70 shadow-[0_24px_80px_-48px_rgba(28,25,23,0.45)] backdrop-blur-sm transition duration-500 hover:-translate-y-1 hover:border-amber-300/80 hover:shadow-[0_30px_90px_-42px_rgba(120,53,15,0.35)] dark:border-white/10 dark:bg-stone-900/65",
        @featured && "md:grid md:grid-cols-[1.15fr_0.85fr]"
      ]}
    >
      <div class={[@featured && "p-8 sm:p-10", !@featured && "p-7 sm:p-8"]}>
        <div class="flex flex-wrap items-center gap-3 text-[0.68rem] font-bold uppercase tracking-[0.2em] text-amber-700 dark:text-amber-400">
          <span :if={@article.category}>{@article.category}</span>
          <span :if={@article.category} class="size-1 rounded-full bg-stone-300 dark:bg-stone-600"></span>
          <time datetime={date_string(@article.date)} class="text-stone-500 dark:text-stone-400">
            {format_date(@article.date)}
          </time>
        </div>
        <h2 class={[
          "mt-5 font-serif font-semibold leading-[1.08] tracking-[-0.035em] text-stone-950 transition-colors group-hover:text-amber-800 dark:text-stone-50 dark:group-hover:text-amber-300",
          if(@featured, do: "text-3xl sm:text-5xl", else: "text-2xl sm:text-3xl")
        ]}>
          <.link href={~p"/#{@article.lang}/#{@article.slug}"} class="after:absolute after:inset-0">
            {@article.title}
          </.link>
        </h2>
        <p class="mt-4 line-clamp-3 text-[0.98rem] leading-7 text-stone-600 dark:text-stone-300">
          {@article.excerpt}
        </p>
        <div class="mt-7 flex items-center justify-between gap-4 border-t border-stone-200/80 pt-5 dark:border-white/10">
          <span class="text-xs font-semibold text-stone-500 dark:text-stone-400">
            {reading_time(@article.body)} min di lettura
          </span>
          <span class="flex items-center gap-2 text-sm font-bold text-stone-900 dark:text-stone-100">
            Leggi
            <.icon
              name="hero-arrow-up-right"
              class="size-4 transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5"
            />
          </span>
        </div>
      </div>
      <div :if={@featured} class="relative hidden min-h-80 overflow-hidden bg-stone-950 md:block">
        <div class="absolute inset-0 bg-[radial-gradient(circle_at_30%_20%,rgba(251,191,36,0.32),transparent_38%),radial-gradient(circle_at_80%_70%,rgba(194,65,12,0.45),transparent_44%),linear-gradient(145deg,#1c1917,#0c0a09)]">
        </div>
        <div class="absolute inset-x-8 bottom-8 border-l border-amber-400/60 pl-5 text-sm leading-6 text-stone-300">
          In evidenza<br />
          <span class="font-serif text-xl text-white">Una lettura scelta per te.</span>
        </div>
      </div>
    </article>
    """
  end

  def format_date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")
  def format_date(_date), do: "Senza data"
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
    article.cover_alt || "Copertina di #{article.title}"
  end
end
