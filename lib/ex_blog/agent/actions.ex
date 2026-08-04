defmodule ExBlog.Agent.Actions do
  @moduledoc """
  Context-aware operational surface shared by Spectre, Telegram, MCP, and tests.

  This module is the imperative half of the agent. Skills declare *what* may be
  requested; `ExBlog.Agent.Actions.Provider` validates a Kinetic action and
  dispatches it here with the current `%Spectre.Context{}`. Functions then read
  content, call an AI boundary, or delegate one filesystem/Git mutation to the
  content layer.

  Keeping execution here provides three useful boundaries:

    * route classification never performs a side effect;
    * policy confirmation happens before a write function is invoked;
    * Telegram, MCP, and tests exercise the same argument normalization and
      response projection instead of growing separate command implementations.

  The optional context carries the normalized input, conversation identifier,
  and injectable test adapters. Public functions also accept `nil` so trusted
  internal callers can use the same operation with explicit arguments.
  """

  alias ExBlog.Agent.ArticleSelections
  alias ExBlog.Agent.ArticleSelector
  alias ExBlog.Agent.Language
  alias ExBlog.Agent.PageAudit
  alias ExBlog.AI
  alias ExBlog.Budget
  alias ExBlog.Config
  alias ExBlog.Content
  alias ExBlog.Content.Sync
  alias ExBlog.Content.Writer
  alias ExBlog.Telegram.Transport
  alias ExBlogWeb.Prompt

  # Read actions return small projections. Full Markdown is exposed only by
  # `read_article/2`, which keeps list/search replies bounded for chat clients.
  @doc "Lists article summaries using explicit arguments or language inferred from the turn."
  @spec list_articles(map(), term()) :: {:ok, map()}
  def list_articles(args, ctx \\ nil) do
    lang = argument(args, :lang) || language_from_text(input_text(ctx)) || :all

    status = status_argument(argument(args, :status))
    articles = Content.list(lang: lang, status: status)

    summaries =
      articles |> Enum.take(ArticleSelections.maximum_entries()) |> Enum.map(&article_summary/1)

    with :ok <- ArticleSelections.remember(conversation_id(ctx), summaries) do
      {:ok,
       %{
         count: length(articles),
         shown_count: length(summaries),
         articles: summaries
       }}
    end
  end

  @doc "Reads one draft or published article identified by language and slug."
  @spec read_article(map(), term()) :: {:ok, map()} | {:error, term()}
  def read_article(args, ctx \\ nil) do
    with {:ok, lang, slug} <- identifier(args, ctx),
         {:ok, article} <- Content.get(lang, slug, published_only?: false) do
      {:ok, article_detail(article)}
    end
  end

  @doc "Searches indexed article metadata and Markdown without mutating content."
  @spec search_articles(map(), term()) :: {:ok, map()}
  def search_articles(args, ctx \\ nil) do
    text = input_text(ctx)
    query = argument(args, :query) || strip_command(text, ["search", "find"])
    lang = argument(args, :lang) || language_from_text(text) || Config.get().default_language
    articles = Content.search(query || "", lang: lang, status: :all)

    summaries =
      articles |> Enum.take(ArticleSelections.maximum_entries()) |> Enum.map(&article_summary/1)

    with :ok <- ArticleSelections.remember(conversation_id(ctx), summaries) do
      {:ok,
       %{
         query: query,
         count: length(articles),
         shown_count: length(summaries),
         articles: summaries
       }}
    end
  end

  @doc "Returns the redacted public configuration projection."
  @spec show_config(map(), term()) :: {:ok, map()}
  def show_config(_args \\ %{}, _ctx \\ nil), do: {:ok, Config.public()}

  @doc "Checks OpenRouter reachability and configured model availability."
  @spec openrouter_status(map(), term()) :: {:ok, map()} | {:error, term()}
  def openrouter_status(_args \\ %{}, _ctx \\ nil), do: AI.health()

  @doc "Returns current AI budget usage without exposing provider credentials."
  @spec budget_status(map(), term()) :: {:ok, map()}
  def budget_status(_args \\ %{}, _ctx \\ nil), do: {:ok, Budget.status()}

  @doc "Returns a bounded operational snapshot of ExBlog and its integrations."
  @spec system_status(map(), term()) :: {:ok, map()}
  def system_status(_args \\ %{}, ctx \\ nil) do
    config = Config.get()

    indexed_articles =
      config.supported_languages
      |> Enum.flat_map(&Content.list(lang: &1, status: :all))
      |> Enum.uniq_by(& &1.path)
      |> length()

    {:ok,
     %{
       system_status: true,
       application: %{status: :running},
       public_url: Config.canonical_url(config),
       content: %{
         status: :ready,
         indexed_articles: indexed_articles,
         languages: config.supported_languages
       },
       telegram: telegram_status(ctx),
       openrouter: openrouter_health(ctx),
       budget: Budget.status()
     }}
  end

  @doc "Runs the bounded Spectre Lens audit for one public blog URL."
  @spec check_page(map(), term()) :: {:ok, PageAudit.result()} | {:error, term()}
  def check_page(args, ctx \\ nil) do
    request = input_text(ctx)
    url = argument(args, :url) || url_from_text(request) || Config.canonical_url()
    focus = argument(args, :focus) || request

    PageAudit.check(url,
      focus: focus,
      conversation_id: conversation_id(ctx),
      estimated_cost_eur: decimal_argument(args, :estimated_cost_eur, "0.02")
    )
  end

  # AI-backed editorial actions generate data first, validate it second, and
  # hand the final mutation to Writer. None of these functions performs policy
  # confirmation; Spectre must have completed that before provider execution.
  @doc "Generates a draft article and optional SEO, then writes it through the Git content layer."
  @spec create_article(map(), term()) :: {:ok, map()} | {:error, term()}
  def create_article(args, ctx \\ nil) do
    request = argument(args, :brief) || input_text(ctx)
    title = argument(args, :title) || title_from_request(request)
    lang = argument(args, :lang) || language_from_text(request) || Config.get().default_language
    category = argument(args, :category)
    slug = argument(args, :slug) || Slug.slugify(title || "")
    subject_ref = "#{lang}/#{slug}"
    proposed_body = argument(args, :body) || argument(args, :proposed_body)

    with :ok <- require_text(title, :title),
         :ok <- require_text(slug, :slug),
         {:ok, body} <- article_body(proposed_body, args, ctx, subject_ref, lang, title, category),
         {:ok, seo} <-
           maybe_generate_seo(
             args,
             ctx,
             %{
               lang: lang,
               title: title,
               category: category,
               cover_alt: argument(args, :cover_alt),
               body: body
             },
             subject_ref
           ),
         {:ok, article} <-
           writer_create(
             Map.merge(
               %{
                 title: title,
                 slug: slug,
                 lang: lang,
                 status: :draft,
                 category: category,
                 tags: argument(args, :tags) || [],
                 cover: argument(args, :cover),
                 cover_alt: argument(args, :cover_alt),
                 body: body
               },
               seo
             ),
             ctx
           ) do
      {:ok, article |> article_summary() |> Map.put(:operation, :created)}
    end
  end

  defp article_body(body, _args, _ctx, _subject_ref, _lang, _title, _category)
       when is_binary(body) do
    body = String.trim(body)

    cond do
      body == "" -> {:error, {:missing_field, :body}}
      String.length(body) > 60_000 -> {:error, {:field_too_long, :body}}
      true -> {:ok, body}
    end
  end

  defp article_body(_body, args, ctx, subject_ref, lang, title, category) do
    prompt =
      Prompt.article_generation(%{
        lang: lang,
        title: title,
        category: category,
        request: argument(args, :brief) || input_text(ctx),
        research_summary: argument(args, :research_summary),
        source_urls: argument(args, :source_urls)
      })

    with {:ok, response} <-
           complete(
             :deep,
             prompt,
             [
               purpose: :article_generation,
               subject_type: "article",
               subject_ref: subject_ref,
               conversation_id: conversation_id(ctx),
               estimated_cost_eur: decimal_argument(args, :estimated_cost_eur, "0.10")
             ],
             ctx
           ),
         body <- response_text(response),
         :ok <- require_text(body, :body) do
      {:ok, body}
    end
  end

  @doc "Builds a revision preview or applies an explicitly supplied approved body."
  @spec revise_article(map(), term()) :: {:ok, map()} | {:error, term()}
  def revise_article(args, ctx \\ nil) do
    with {:ok, lang, slug} <- identifier(args, ctx),
         {:ok, article} <- Content.get(lang, slug, published_only?: false) do
      case argument(args, :proposed_body) do
        body when is_binary(body) ->
          apply_revision(article, body)

        _missing ->
          preview_revision(article, argument(args, :instructions) || input_text(ctx), args, ctx)
      end
    end
  end

  @doc "Translates an article and creates a linked draft in the target language."
  @spec translate_article(map(), term()) :: {:ok, map()} | {:error, term()}
  def translate_article(args, ctx \\ nil) do
    target = argument(args, :target_lang) || target_language(input_text(ctx))

    with {:ok, source_lang, slug} <- identifier(args, ctx),
         {:ok, article} <- Content.get(source_lang, slug, published_only?: false),
         :ok <- supported_language(target),
         {:ok, response} <-
           complete(
             :deep,
             translation_prompt(article, target),
             [
               purpose: :translation,
               subject_type: "article",
               subject_ref: article.path,
               conversation_id: conversation_id(ctx),
               estimated_cost_eur: decimal_argument(args, :estimated_cost_eur, "0.08")
             ],
             ctx
           ),
         {:ok, translated} <-
           Writer.create(%{
             title: argument(args, :title) || article.title,
             lang: target,
             status: :draft,
             category: article.category,
             tags: article.tags,
             cover: article.cover,
             cover_alt: article.cover_alt,
             translation_of: article.path,
             body: response_text(response)
           }) do
      {:ok, translated |> article_summary() |> Map.put(:operation, :created)}
    end
  end

  @doc "Generates bounded SEO metadata and commits it to an existing article."
  @spec generate_seo(map(), term()) :: {:ok, map()} | {:error, term()}
  def generate_seo(args, ctx \\ nil) do
    with {:ok, lang, slug} <- identifier(args, ctx),
         {:ok, article} <- Content.get(lang, slug, published_only?: false),
         {:ok, generated} <- seo_metadata(article, args, ctx, article.path),
         seo <- preserve_editorial_metadata(generated, article),
         {:ok, updated} <-
           Writer.update(article, Map.put(seo, :updated, Date.utc_today())) do
      {:ok, article_summary(updated)}
    end
  end

  # Status and destructive operations share identifier parsing and delegate the
  # actual transaction to Writer, which owns safe paths, commits, and pushes.
  @doc "Publishes an existing draft through the canonical Writer transaction."
  @spec publish_article(map(), term()) :: {:ok, map()} | {:error, term()}
  def publish_article(args, ctx \\ nil) do
    mutate_article(args, ctx, &Writer.publish/1, :published)
  end

  @doc "Returns a published article to draft status."
  @spec unpublish_article(map(), term()) :: {:ok, map()} | {:error, term()}
  def unpublish_article(args, ctx \\ nil) do
    mutate_article(args, ctx, &Writer.unpublish/1, :unpublished)
  end

  @doc "Deletes one identified article through the protected Writer boundary."
  @spec delete_article(map(), term()) :: {:ok, map()} | {:error, term()}
  def delete_article(args, ctx \\ nil) do
    with {:ok, lang, slug} <- identifier(args, ctx),
         {:ok, article} <- Content.get(lang, slug, published_only?: false),
         :ok <- Writer.delete(article) do
      {:ok, %{deleted: true, lang: lang, slug: slug}}
    end
  end

  @doc "Synchronizes the canonical branch and rebuilds the in-memory content index."
  @spec sync_repository(map(), term()) :: {:ok, map()} | {:error, term()}
  def sync_repository(_args \\ %{}, _ctx \\ nil), do: Sync.sync_now()

  # Revision previews are intentionally two-phase. The model may propose text,
  # but applying it is a separate invocation with `proposed_body` present.
  defp preview_revision(article, instructions, args, ctx) do
    level = if truthy?(argument(args, :major)), do: :deep, else: :balanced

    prompt = Prompt.article_revision(%{instructions: instructions, body: article.body})

    with {:ok, response} <-
           complete(
             level,
             prompt,
             [
               purpose: :article_revision,
               subject_type: "article",
               subject_ref: article.path,
               conversation_id: conversation_id(ctx),
               estimated_cost_eur: decimal_argument(args, :estimated_cost_eur, "0.05")
             ],
             ctx
           ) do
      proposed = response_text(response)

      {:ok,
       %{
         lang: article.lang,
         slug: article.slug,
         proposed_body: proposed,
         diff: diff(article.body, proposed),
         requires_confirmation: true
       }}
    end
  end

  defp mutate_article(args, ctx, operation, result_operation) do
    with {:ok, lang, slug} <- identifier(args, ctx),
         {:ok, article} <- Content.get(lang, slug, published_only?: false),
         {:ok, updated} <- article_mutation(article, operation, result_operation, ctx) do
      {:ok, updated |> article_summary() |> Map.put(:operation, result_operation)}
    end
  end

  defp article_mutation(article, operation, result_operation, ctx) do
    case context_option(ctx, :article_mutator) do
      fun when is_function(fun, 2) -> fun.(result_operation, article)
      fun when is_function(fun, 1) -> fun.(article)
      _default -> operation.(article)
    end
  end

  defp apply_revision(article, body) do
    with {:ok, updated} <- Writer.update(article, %{body: body, updated: Date.utc_today()}) do
      {:ok, updated |> article_summary() |> Map.put(:operation, :revised)}
    end
  end

  # Argument helpers accept atom or string keys because Kinetic, MCP, and direct
  # Elixir callers use different map conventions. No user value becomes an atom.
  defp identifier(args, ctx) do
    lang = argument(args, :lang)
    slug = argument(args, :slug)

    if is_binary(lang) and is_binary(slug),
      do: {:ok, lang, slug},
      else: identifier_from_context(ctx)
  end

  defp identifier_from_context(ctx) do
    text = input_text(ctx)

    with {:error, :article_identifier_required} <- identifier_from_text(text),
         {:ok, article} <-
           ArticleSelector.resolve(text || "", conversation_id: conversation_id(ctx)) do
      {:ok, article.lang, article.slug}
    end
  end

  defp identifier_from_text(text) do
    languages = Config.get().supported_languages |> Enum.map_join("|", &Regex.escape/1)
    regex = ~r/(?:^|\s)(#{languages})[\s\/:]+([a-z0-9]+(?:-[a-z0-9]+)*)(?:\s|$)/i

    case Regex.run(regex, text || "", capture: :all_but_first) do
      [lang, slug] -> {:ok, String.downcase(lang), String.downcase(slug)}
      _other -> {:error, :article_identifier_required}
    end
  end

  defp language_from_text(nil), do: nil

  defp language_from_text(text) do
    Language.code_in(text, Config.get().supported_languages)
  end

  defp target_language(nil), do: nil

  defp target_language(text) do
    case Language.parse_target(text, Config.get().supported_languages) do
      {:ok, language} -> language
      :error -> nil
    end
  end

  defp supported_language(lang) when is_binary(lang) do
    if lang in Config.get().supported_languages, do: :ok, else: {:error, :unsupported_language}
  end

  defp supported_language(_lang), do: {:error, :target_language_required}

  defp title_from_request(nil), do: nil

  defp title_from_request(text) do
    text
    |> String.replace(
      ~r/^\/?(?:create|write)(?:\s+me)?(?:\s+an?)?(?:\s+(?:article|post))?(?:\s+about)?\s*/iu,
      ""
    )
    |> String.trim()
    |> case do
      "" -> nil
      title -> String.slice(title, 0, 160)
    end
  end

  defp url_from_text(nil), do: nil

  defp url_from_text(text) do
    case Regex.run(~r/https?:\/\/[^\s<>"']+/iu, text) do
      [url] -> Regex.replace(~r/[.,;:!?\)\]\}]+$/u, url, "")
      _other -> nil
    end
  end

  defp translation_prompt(article, target),
    do:
      Prompt.article_translation(%{
        source_lang: article.lang,
        target_lang: target,
        body: article.body
      })

  defp seo_prompt(article),
    do:
      Prompt.article_seo(%{
        lang: article.lang,
        title: article.title,
        category: article.category,
        cover_alt: article.cover_alt,
        body: article.body
      })

  defp maybe_generate_seo(args, ctx, article, subject_ref) do
    if truthy?(argument(args, :generate_seo)) do
      with {:ok, generated} <- seo_metadata(article, args, ctx, subject_ref) do
        requested_alt = nonblank_string(Map.get(article, :cover_alt))
        requested_tags = normalized_tags(argument(args, :tags))

        {:ok,
         generated
         |> Map.put(:cover_alt, requested_alt || generated.cover_alt)
         |> Map.put(:tags, Enum.take(Enum.uniq(requested_tags ++ generated.tags), 8))}
      end
    else
      {:ok, %{}}
    end
  end

  # Model output crosses a strict JSON boundary before Writer receives it. Each
  # string and tag is length-limited again after decoding.
  defp seo_metadata(%ExBlog.Content.Article{} = article, args, ctx, subject_ref) do
    with {:ok, response} <-
           complete(
             :balanced,
             seo_prompt(article),
             seo_options(args, ctx, subject_ref),
             ctx
           ),
         {:ok, decoded} <- decode_json(response_text(response)) do
      normalize_seo(decoded)
    end
  end

  defp seo_metadata(article, args, ctx, subject_ref) when is_map(article) do
    with {:ok, response} <-
           complete(
             :balanced,
             Prompt.article_seo(article),
             seo_options(args, ctx, subject_ref),
             ctx
           ),
         {:ok, decoded} <- decode_json(response_text(response)) do
      normalize_seo(decoded)
    end
  end

  defp seo_options(args, ctx, subject_ref) do
    estimated_cost =
      argument(args, :seo_estimated_cost_eur) ||
        decimal_argument(args, :estimated_cost_eur, "0.02")

    [
      purpose: :seo_generation,
      subject_type: "article",
      subject_ref: subject_ref,
      conversation_id: conversation_id(ctx),
      estimated_cost_eur: estimated_cost
    ]
  end

  defp normalize_seo(seo) do
    with {:ok, seo_title} <- bounded_json_string(seo, "seo_title", 60, true),
         {:ok, seo_description} <- bounded_json_string(seo, "seo_description", 160, true),
         {:ok, cover_alt} <- bounded_json_string(seo, "cover_alt", 500, false) do
      {:ok,
       %{
         seo_title: seo_title,
         seo_description: seo_description,
         cover_alt: cover_alt,
         tags: normalized_tags(Map.get(seo, "tags"))
       }}
    end
  end

  defp bounded_json_string(map, key, maximum, required?) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        value = value |> String.trim() |> String.slice(0, maximum)

        if value == "" and required?,
          do: {:error, {:invalid_model_field, key}},
          else: {:ok, empty_to_nil(value)}

      nil when not required? ->
        {:ok, nil}

      _invalid ->
        {:error, {:invalid_model_field, key}}
    end
  end

  defp normalized_tags(tags) when is_list(tags) do
    tags
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&(String.trim(&1) |> String.slice(0, 50)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.take(6)
  end

  defp normalized_tags(_tags), do: []

  defp preserve_editorial_metadata(generated, article) do
    generated
    |> Map.put(:cover_alt, article.cover_alt || generated.cover_alt)
    |> Map.put(:tags, Enum.take(Enum.uniq(article.tags ++ generated.tags), 8))
  end

  # Tests can inject `:ai_complete`; production always reaches the budgeted
  # `ExBlog.AI` boundary through the same call site.
  defp complete(level, prompt, opts, ctx) do
    opts = maybe_put_req_options(opts, ctx)

    case context_option(ctx, :ai_complete) do
      fun when is_function(fun, 3) -> fun.(level, prompt, opts)
      _default -> AI.complete(level, prompt, opts)
    end
  end

  defp maybe_put_req_options(opts, ctx) do
    case context_option(ctx, :req_options) do
      req_options when is_list(req_options) -> Keyword.put(opts, :req_options, req_options)
      _missing -> opts
    end
  end

  defp context_option(%{opts: opts}, key) when is_list(opts), do: Keyword.get(opts, key)
  defp context_option(_ctx, _key), do: nil

  defp telegram_status(ctx) do
    snapshot =
      case context_option(ctx, :telegram_snapshot) do
        fun when is_function(fun, 0) -> fun.()
        snapshot when is_map(snapshot) -> snapshot
        _default -> default_telegram_snapshot()
      end

    case snapshot do
      snapshot when is_map(snapshot) ->
        %{
          connection_status: Map.get(snapshot, :connection_status, :unknown),
          auth_state: Map.get(snapshot, :auth_state, :unknown),
          last_error?: Map.get(snapshot, :last_error?, false) == true
        }

      _invalid ->
        %{connection_status: :unavailable, auth_state: :unknown, last_error?: true}
    end
  rescue
    _exception -> %{connection_status: :unavailable, auth_state: :unknown, last_error?: true}
  catch
    :exit, _reason ->
      %{connection_status: :unavailable, auth_state: :unknown, last_error?: true}
  end

  defp default_telegram_snapshot do
    case Process.whereis(Transport) do
      pid when is_pid(pid) -> Transport.snapshot(pid)
      nil -> %{connection_status: :not_started, auth_state: :not_started, last_error?: false}
    end
  end

  defp openrouter_health(ctx) do
    result =
      case context_option(ctx, :openrouter_health) do
        fun when is_function(fun, 0) -> fun.()
        _default -> AI.health()
      end

    case result do
      {:ok, status} when is_map(status) -> status
      {:error, reason} -> unavailable_openrouter(reason)
      _invalid -> unavailable_openrouter(:invalid_health_response)
    end
  rescue
    _exception -> unavailable_openrouter(:health_check_failed)
  catch
    :exit, _reason -> unavailable_openrouter(:health_check_failed)
  end

  defp unavailable_openrouter(reason) do
    %{
      configured: true,
      reachable: false,
      models_available: false,
      reason: health_reason(reason)
    }
  end

  defp health_reason({reason, _detail}) when is_atom(reason), do: reason
  defp health_reason(reason) when is_atom(reason), do: reason
  defp health_reason(_reason), do: :unavailable

  defp writer_create(params, ctx) do
    writer_opts =
      case context_option(ctx, :article_asset_root) do
        root when is_binary(root) -> [asset_source_root: root]
        _default -> []
      end

    case context_option(ctx, :article_writer) do
      fun when is_function(fun, 2) -> fun.(params, writer_opts)
      fun when is_function(fun, 1) -> fun.(params)
      _default -> Writer.create(params, writer_opts)
    end
  end

  defp decode_json(text) do
    text =
      text
      |> String.trim()
      |> String.replace(~r/^```(?:json)?\s*/i, "")
      |> String.replace(~r/\s*```$/, "")

    case Jason.decode(text) do
      {:ok, value} when is_map(value) -> {:ok, value}
      _other -> {:error, :invalid_model_json}
    end
  end

  defp diff(old, new) do
    old_lines = String.split(old, "\n")
    new_lines = String.split(new, "\n")

    List.myers_difference(old_lines, new_lines)
    |> Enum.flat_map(fn
      {:eq, lines} -> Enum.map(lines, &("  " <> &1))
      {:del, lines} -> Enum.map(lines, &("- " <> &1))
      {:ins, lines} -> Enum.map(lines, &("+ " <> &1))
    end)
    |> Enum.join("\n")
    |> String.slice(0, 16_000)
  end

  # Chat projections deliberately omit internal parser and Git bookkeeping.
  defp article_summary(article) do
    %{
      title: article.title,
      slug: article.slug,
      lang: article.lang,
      status: article.status,
      date: date_string(article.date),
      category: article.category,
      tags: article.tags,
      seo_title: article.seo_title,
      seo_description: article.seo_description,
      cover: article.cover,
      cover_alt: article.cover_alt,
      path: article.path,
      source_url: Config.repository_file_url(article.path),
      public_url:
        if(article.status == :published,
          do: Config.public_article_url(article.lang, article.slug),
          else: nil
        )
    }
  end

  defp article_detail(article) do
    article
    |> article_summary()
    |> Map.merge(%{
      updated: date_string(article.updated),
      seo_title: article.seo_title,
      seo_description: article.seo_description,
      cover: article.cover,
      cover_alt: article.cover_alt,
      translation_of: article.translation_of,
      body: article.body
    })
  end

  defp status_argument(value) when value in [:draft, "draft"], do: :draft
  defp status_argument(value) when value in [:published, "published"], do: :published
  defp status_argument(value) when value in [:all, "all", "tutti"], do: :all
  defp status_argument(_value), do: :all

  defp strip_command(nil, _commands), do: nil

  defp strip_command(text, commands) do
    Enum.reduce(commands, text, fn command, value ->
      String.replace(value, ~r/^#{Regex.escape(command)}\s*/iu, "")
    end)
    |> String.trim()
  end

  defp response_text(%{text: text}) when is_binary(text), do: String.trim(text)
  defp response_text(%{"text" => text}) when is_binary(text), do: String.trim(text)
  defp response_text(_response), do: ""

  defp input_text(%{input: %{text: text}}) when is_binary(text), do: text
  defp input_text(_ctx), do: nil

  defp conversation_id(%{state: %{conversation_id: value}}) when not is_nil(value),
    do: to_string(value)

  defp conversation_id(_ctx), do: nil

  defp argument(args, key), do: Map.get(args, key, Map.get(args, Atom.to_string(key)))

  defp decimal_argument(args, key, default) do
    case argument(args, key) do
      value when is_binary(value) -> value
      value when is_number(value) -> value
      _other -> default
    end
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
  defp nonblank_string(value) when is_binary(value), do: value |> String.trim() |> empty_to_nil()
  defp nonblank_string(_value), do: nil
  defp require_text(value, _field) when is_binary(value) and value != "", do: :ok
  defp require_text(_value, field), do: {:error, {:missing_field, field}}
  defp date_string(%Date{} = date), do: Date.to_iso8601(date)
  defp date_string(_date), do: nil
end
