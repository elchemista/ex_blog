defmodule ExBlogWeb.MCP.Tools do
  @moduledoc false

  alias ExBlog.Agent.Actions

  @spec list() :: [map()]
  def list do
    [
      tool(
        "list_articles",
        "List blog articles without returning their full Markdown bodies.",
        schema(%{
          lang: language_schema(),
          status: enum_schema(["published", "draft", "all"])
        }),
        read_only: true
      ),
      tool(
        "read_article",
        "Read one complete article. Use this before proposing or applying an edit.",
        article_identifier_schema(),
        read_only: true
      ),
      tool(
        "search_articles",
        "Search titles, categories, tags, and Markdown content.",
        schema(%{query: string_schema("Search terms", 500), lang: language_schema()}, ["query"]),
        read_only: true
      ),
      tool(
        "show_config",
        "Show the safe deployment configuration. Credential values are never returned.",
        schema(%{}),
        read_only: true
      ),
      tool(
        "openrouter_status",
        "Check whether OpenRouter is reachable and the configured model IDs exist. Never returns the API key.",
        schema(%{}),
        read_only: true,
        open_world: true
      ),
      tool(
        "budget_status",
        "Show current daily and monthly LLM spend and remaining budget.",
        schema(%{}),
        read_only: true
      ),
      tool(
        "check_page",
        "Open a rendered public page with Spectre Lens and assess its content, structure, accessibility, and SEO baseline.",
        schema(%{
          url:
            string_schema(
              "Absolute public HTTP(S) URL; defaults to the configured blog URL",
              2_048
            ),
          focus: string_schema("Optional aspect to inspect", 2_000),
          estimated_cost_eur: cost_schema()
        }),
        read_only: true,
        open_world: true
      ),
      tool(
        "create_article",
        "Generate a draft body and optional SEO metadata with OpenRouter, then commit the Markdown. Obtain confirmation before calling.",
        schema(
          %{
            title: string_schema("Article title", 160),
            slug: slug_schema(),
            lang: language_schema(),
            category: string_schema("Optional category", 120),
            brief: string_schema("Editorial brief used for article generation", 8_000),
            tags: tags_schema(),
            generate_seo: %{
              type: "boolean",
              description: "Also generate SEO title, description, image alt text, and tags"
            },
            cover: string_schema("Optional HTTPS URL or /images public path", 2_048),
            cover_alt: string_schema("Optional accessible cover description", 500),
            estimated_cost_eur: cost_schema()
          },
          ["title", "brief"]
        ),
        read_only: false,
        destructive: false,
        open_world: true
      ),
      tool(
        "revise_article",
        "Preview an AI revision, or apply an explicitly confirmed proposed_body. Read the article first.",
        schema(
          Map.merge(article_identifier_properties(), %{
            instructions: string_schema("Requested revision", 8_000),
            proposed_body: string_schema("Exact confirmed Markdown body to apply", 100_000),
            major: %{type: "boolean"},
            estimated_cost_eur: cost_schema()
          }),
          ["lang", "slug"]
        ),
        read_only: false,
        destructive: true,
        open_world: true
      ),
      tool(
        "translate_article",
        "Translate an article and commit the translation as a new draft.",
        schema(
          Map.merge(article_identifier_properties(), %{
            target_lang: language_schema(),
            title: string_schema("Optional translated title", 160),
            estimated_cost_eur: cost_schema()
          }),
          ["lang", "slug", "target_lang"]
        ),
        read_only: false,
        destructive: false,
        open_world: true
      ),
      tool(
        "generate_seo",
        "Generate and commit SEO metadata for an existing article.",
        schema(
          Map.put(article_identifier_properties(), :estimated_cost_eur, cost_schema()),
          ["lang", "slug"]
        ),
        read_only: false,
        destructive: true,
        open_world: true
      ),
      mutation_tool("publish_article", "Publish an existing draft after explicit confirmation."),
      mutation_tool(
        "unpublish_article",
        "Return a published article to draft after explicit confirmation."
      ),
      mutation_tool(
        "delete_article",
        "Delete an article from the repository after explicit confirmation.",
        destructive: true,
        idempotent: false
      ),
      tool(
        "sync_repository",
        "Fetch the configured Git branch and rebuild the content index.",
        schema(%{}),
        read_only: false,
        destructive: false,
        idempotent: true,
        open_world: true
      )
    ]
  end

  @spec call(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def call(name, arguments) when is_binary(name) and is_map(arguments) do
    dispatch(name, arguments)
  end

  def call(_name, _arguments), do: {:error, :invalid_arguments}

  defp dispatch("list_articles", arguments), do: Actions.list_articles(arguments)
  defp dispatch("read_article", arguments), do: Actions.read_article(arguments)
  defp dispatch("search_articles", arguments), do: Actions.search_articles(arguments)
  defp dispatch("show_config", arguments), do: Actions.show_config(arguments)
  defp dispatch("openrouter_status", arguments), do: Actions.openrouter_status(arguments)
  defp dispatch("budget_status", arguments), do: Actions.budget_status(arguments)
  defp dispatch("check_page", arguments), do: Actions.check_page(arguments)
  defp dispatch("create_article", arguments), do: Actions.create_article(arguments)
  defp dispatch("revise_article", arguments), do: Actions.revise_article(arguments)
  defp dispatch("translate_article", arguments), do: Actions.translate_article(arguments)
  defp dispatch("generate_seo", arguments), do: Actions.generate_seo(arguments)
  defp dispatch("publish_article", arguments), do: Actions.publish_article(arguments)
  defp dispatch("unpublish_article", arguments), do: Actions.unpublish_article(arguments)
  defp dispatch("delete_article", arguments), do: Actions.delete_article(arguments)
  defp dispatch("sync_repository", arguments), do: Actions.sync_repository(arguments)
  defp dispatch(_name, _arguments), do: {:error, :tool_not_found}

  defp mutation_tool(name, description, opts \\ []) do
    tool(name, description, article_identifier_schema(),
      read_only: false,
      destructive: Keyword.get(opts, :destructive, true),
      idempotent: Keyword.get(opts, :idempotent, true),
      open_world: true
    )
  end

  defp tool(name, description, input_schema, opts) do
    read_only = Keyword.fetch!(opts, :read_only)

    %{
      name: name,
      title: name |> String.replace("_", " ") |> String.capitalize(),
      description: description,
      inputSchema: input_schema,
      outputSchema: %{type: "object", additionalProperties: true},
      annotations: %{
        readOnlyHint: read_only,
        destructiveHint: Keyword.get(opts, :destructive, false),
        idempotentHint: Keyword.get(opts, :idempotent, read_only),
        openWorldHint: Keyword.get(opts, :open_world, false)
      }
    }
  end

  defp article_identifier_schema do
    schema(article_identifier_properties(), ["lang", "slug"])
  end

  defp article_identifier_properties do
    %{lang: language_schema(), slug: slug_schema()}
  end

  defp schema(properties, required \\ []) do
    %{type: "object", properties: properties, required: required, additionalProperties: false}
  end

  defp language_schema,
    do: string_schema("Configured language code such as it or en", 32)

  defp slug_schema do
    %{
      type: "string",
      description: "Canonical lowercase article slug",
      pattern: "^[a-z0-9]+(?:-[a-z0-9]+)*$",
      maxLength: 200
    }
  end

  defp tags_schema,
    do: %{type: "array", items: string_schema("Tag", 80), maxItems: 30}

  defp cost_schema,
    do: %{type: ["number", "string"], description: "Conservative estimated cost in EUR"}

  defp string_schema(description, maximum),
    do: %{type: "string", description: description, minLength: 1, maxLength: maximum}

  defp enum_schema(values), do: %{type: "string", enum: values}
end
