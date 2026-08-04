defmodule ExBlog.Agent.ArticleSelectorTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Agent.Actions
  alias ExBlog.Agent.ArticleSelections
  alias ExBlog.Agent.ArticleSelector
  alias ExBlog.Agent.Presenter
  alias ExBlog.Content.Index

  test "a numbered list can be reused by number, title, ID, slug, or link" do
    root = temporary_directory()
    english = Path.join([root, "content", "en"])
    File.mkdir_p!(english)

    for number <- 1..5 do
      status = if number == 5, do: "published", else: "draft"

      File.write!(
        Path.join(english, "2026-08-0#{number}-article-#{number}.md"),
        article("Article #{number}", "article-#{number}", status, "2026-08-0#{number}")
      )
    end

    start_supervised!({Index, root: root, content_root: "content"})
    on_exit(fn -> File.rm_rf!(root) end)
    conversation_id = "numbered-list"

    assert {:ok, result} =
             Actions.list_articles(%{}, %{
               input: %{text: "list articles"},
               state: %{conversation_id: conversation_id}
             })

    rendered = Presenter.present(result)
    assert rendered =~ "1. [en] Article 5"
    assert rendered =~ "5. [en] Article 1"
    assert rendered =~ "edit article 2"
    assert rendered =~ "exact title"

    assert {:ok, entries} = ArticleSelections.recall(conversation_id)
    assert Enum.map(entries, & &1.slug) == ~w(article-5 article-4 article-3 article-2 article-1)

    assert {:ok, selected_by_number} =
             ArticleSelector.resolve("publish 4 article", conversation_id: conversation_id)

    assert selected_by_number.slug == "article-2"

    assert {:ok, selected_by_title} =
             ArticleSelector.resolve("edit article: Article 3", conversation_id: conversation_id)

    assert selected_by_title.slug == "article-3"

    assert {:ok, selected_by_id} = ArticleSelector.resolve("publish en/article-4")
    assert selected_by_id.slug == "article-4"

    assert {:ok, selected_by_slug} = ArticleSelector.resolve("edit article-1")
    assert selected_by_slug.slug == "article-1"

    published = Enum.find(result.articles, &(&1.slug == "article-5"))
    draft = Enum.find(result.articles, &(&1.slug == "article-2"))

    assert {:ok, selected_by_public_link} =
             ArticleSelector.resolve("publish #{published.public_url}")

    assert selected_by_public_link.slug == "article-5"

    assert {:ok, selected_by_git_link} =
             ArticleSelector.resolve("edit #{draft.source_url}")

    assert selected_by_git_link.slug == "article-2"
  end

  test "number selection fails clearly without a current list or outside its range" do
    assert {:error, :article_list_required} =
             ArticleSelector.resolve("publish article 2", conversation_id: "missing-list")

    assert :ok = ArticleSelections.remember("short-list", [%{lang: "en", slug: "one"}])

    assert {:error, {:article_number_out_of_range, 2}} =
             ArticleSelector.resolve("publish article 2", conversation_id: "short-list")
  end

  defp article(title, slug, status, date) do
    """
    ---
    title: #{title}
    slug: #{slug}
    lang: en
    status: #{status}
    date: #{date}
    tags: []
    ---
    #{title} body.
    """
  end

  defp temporary_directory do
    path =
      Path.join(
        System.tmp_dir!(),
        "ex-blog-selector-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end
end
