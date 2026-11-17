defmodule ExBlogWeb.DocumentationHTML do
  @moduledoc false
  use ExBlogWeb, :html

  embed_templates "documentation_html/*"

  attr :chapters, :list, required: true
  attr :language, :string, required: true
  attr :current, :string, default: nil
  attr :prefix, :string, required: true

  defp chapter_navigation(assigns) do
    ~H"""
    <ol class="space-y-1">
      <li :for={{chapter, index} <- Enum.with_index(@chapters, 1)}>
        <.link
          id={"#{@prefix}-#{chapter.slug}"}
          href={~p"/#{@language}/docs/#{chapter.slug}"}
          aria-current={if(chapter.slug == @current, do: "page", else: nil)}
          class={[
            "flex gap-3 border-l-2 py-2 pl-3 pr-2 text-[0.72rem] leading-5 transition",
            if(chapter.slug == @current,
              do: "border-[color:var(--fg)] bg-[color:var(--surface-bar)] t-strong",
              else: "border-transparent t-dim hover:border-[color:var(--line)] hover:t-strong"
            )
          ]}
        >
          <span aria-hidden="true" class="shrink-0 t-faint">
            {String.pad_leading("#{index}", 2, "0")}
          </span>
          <span>{chapter.title}</span>
        </.link>
      </li>
    </ol>
    """
  end
end
