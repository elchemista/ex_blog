defmodule ExBlog.Content.IndexTest do
  use ExUnit.Case, async: false

  alias ExBlog.Content.Index

  setup do
    root = temporary_directory("index")
    content = Path.join([root, "content", "it"])
    File.mkdir_p!(content)

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, content: content}
  end

  test "indexes valid and malformed files without failing startup", %{
    root: root,
    content: content
  } do
    File.write!(Path.join(content, "2026-08-03-valid.md"), article("Valid", "valid"))
    File.write!(Path.join(content, "broken.md"), "not front matter")

    start_supervised!({Index, root: root, content_root: "content"})

    assert Index.get("it", "valid").title == "Valid"
    assert Index.stats().total == 1
    assert Index.stats().invalid == 1
  end

  test "a rebuild exposes a complete replacement snapshot", %{root: root, content: content} do
    path = Path.join(content, "2026-08-03-first.md")
    File.write!(path, article("First", "first"))
    start_supervised!({Index, root: root, content_root: "content"})

    File.rm!(path)
    File.write!(Path.join(content, "2026-08-04-second.md"), article("Second", "second"))

    readers =
      for _index <- 1..20 do
        Task.async(fn -> Enum.map(Index.all(), & &1.slug) end)
      end

    assert {:ok, %{total: 1}} = Index.rebuild()
    snapshots = Task.await_many(readers)

    assert Enum.all?(snapshots, &(&1 in [["first"], ["second"]]))
    assert Index.get("it", "first") == nil
    assert Index.get("it", "second").title == "Second"
  end

  defp article(title, slug) do
    """
    ---
    title: #{title}
    slug: #{slug}
    lang: it
    status: published
    date: 2026-08-03
    tags: []
    ---
    # #{title}
    """
  end

  defp temporary_directory(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "ex-blog-#{label}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end
end
