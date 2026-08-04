defmodule ExBlog.Agent.RouterPipelineTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Agent
  alias Spectre.Router
  alias Spectre.Router.SemanticCache

  defmodule SimilarityEmbedding do
    @moduledoc false

    @behaviour Spectre.Classifier.Embedding

    @impl Spectre.Classifier.Embedding
    def load(_model, _opts), do: {:ok, 3}

    @impl Spectre.Classifier.Embedding
    def download(model, opts), do: load(model, opts)

    @impl Spectre.Classifier.Embedding
    def embed(text, _opts) do
      text = text |> to_string() |> String.downcase()

      vector =
        cond do
          String.contains?(text, ["search", "find", "locate", "discusses"]) ->
            [0.0, 1.0, 0.0]

          String.contains?(text, ["inventory", "complete archive", "list the blog", "archived"]) ->
            [1.0, 0.0, 0.0]

          true ->
            [0.0, 0.0, 1.0]
        end

      capture({:embedding_called, text})
      {:ok, vector}
    end

    defp capture(message) do
      if pid = Application.get_env(:ex_blog, :router_capture_pid), do: send(pid, message)
    end
  end

  defmodule CaptureClassifier do
    @moduledoc false

    @behaviour Spectre.LLM

    @impl Spectre.LLM
    def complete(prompt, opts) do
      if pid = Application.get_env(:ex_blog, :router_capture_pid) do
        send(pid, {:classifier_called, prompt, opts})
      end

      {:ok, Application.get_env(:ex_blog, :router_classifier_label, "SEARCH_ARTICLES")}
    end
  end

  defmodule CaptureLocalClassifier do
    @moduledoc false

    def classify(text, _opts) do
      if pid = Application.get_env(:ex_blog, :router_capture_pid) do
        send(pid, {:local_classifier_called, text})
      end

      label = Application.get_env(:ex_blog, :router_local_classifier_label, "LIST_ARTICLES")

      {:ok,
       %{
         label: label,
         accepted?: true,
         confidence: 0.97,
         margin: 0.21,
         strategy: :local_classifier
       }}
    end
  end

  defmodule ClassifierAgent do
    @moduledoc false

    use Spectre.Agent

    classifier(ExBlog.Agent.RouterPipelineTest.CaptureClassifier,
      prompt: &ExBlogWeb.Prompt.classifier/1,
      label_examples: 3,
      llm_opts: [temperature: 0.0, max_tokens: 16]
    )

    router(
      pipeline: ExBlog.Agent.RouterPipeline,
      via: [:llm_classifier],
      semantic_cache?: false,
      terminal_labels: [:SEARCH_ARTICLES, :SHOW_AI_BUDGET, :UNKNOWN]
    )

    flow :blog do
      on :SEARCH_ARTICLES,
        embedding: [
          "search the article archive",
          "find blog posts about a topic",
          "locate content that discusses a subject"
        ],
        via: [:llm_classifier],
        cache: false do
        reply("search")
      end

      on :SHOW_AI_BUDGET,
        embedding: [
          "show the AI budget",
          "how much has the agent spent",
          "report the remaining monthly model allowance"
        ],
        via: [:classifier, :llm_classifier],
        cache: false do
        reply("budget")
      end
    end

    flow :fallback do
      on :UNKNOWN, via: [:llm_classifier], cache: false do
        reply("unknown")
      end
    end
  end

  setup do
    previous_capture = Application.get_env(:ex_blog, :router_capture_pid)
    previous_classifier_label = Application.get_env(:ex_blog, :router_classifier_label)
    previous_local_label = Application.get_env(:ex_blog, :router_local_classifier_label)
    Application.put_env(:ex_blog, :router_capture_pid, self())
    :ok = SemanticCache.clear(Agent)

    on_exit(fn ->
      :ok = SemanticCache.clear(Agent)
      restore_env(:router_capture_pid, previous_capture)
      restore_env(:router_classifier_label, previous_classifier_label)
      restore_env(:router_local_classifier_label, previous_local_label)
    end)

    :ok
  end

  test "skill routes explicitly expose semantic and LLM providers without command regex" do
    router = Agent.__spectre_router__()

    assert Keyword.fetch!(router, :via) ==
             [:regex, :classifier, :semantic_cache, :llm_classifier]

    refute Keyword.fetch!(router, :classifier_history)
    refute Keyword.fetch!(router, :semantic_learn?)

    rules = rules_by_label()
    read_via = [:embedding, :classifier, :semantic_cache, :llm_classifier]
    mutation_via = [:embedding, :classifier, :llm_classifier]

    for label <- [
          :LIST_ARTICLES,
          :READ_ARTICLE,
          :SEARCH_ARTICLES,
          :CHECK_BLOG_PAGE,
          :SHOW_CAPABILITIES,
          :SHOW_BLOG_CONFIG,
          :SHOW_AI_BUDGET,
          :SHOW_SYSTEM_STATUS,
          :CHECK_OPENROUTER,
          :SHOW_VERIFICATION
        ] do
      rule = Map.fetch!(rules, label)
      assert rule.via == read_via
      assert rule.cache
      assert rule.learn
      assert length(rule.embedding) == 3
      assert rule.regex == []
    end

    for label <- [
          :START_ARTICLE_CREATION,
          :REVISE_ARTICLE,
          :TRANSLATE_ARTICLE,
          :GENERATE_ARTICLE_SEO,
          :PUBLISH_ARTICLE,
          :UNPUBLISH_ARTICLE,
          :DELETE_ARTICLE,
          :SYNC_BLOG_REPOSITORY,
          :VERIFY_BLOG
        ] do
      rule = Map.fetch!(rules, label)
      assert rule.via == mutation_via
      refute rule.cache
      refute rule.learn
      assert length(rule.embedding) == 3
      assert rule.regex == []
    end

    ask_ai = Map.fetch!(rules, :ASK_AI)
    assert ask_ai.via == read_via
    assert ask_ai.cache
    refute ask_ai.learn
    assert length(ask_ai.embedding) == 3

    unknown = Map.fetch!(rules, :UNKNOWN)
    assert unknown.via == [:llm_classifier]
    assert {:reason, :unknown_request, _opts} = unknown.handler

    for label <- [
          :CAPTURE_ARTICLE_BRIEF,
          :CAPTURE_ARTICLE_LANGUAGE,
          :CAPTURE_ARTICLE_CATEGORY,
          :CAPTURE_ARTICLE_TITLE,
          :CAPTURE_ARTICLE_SEO
        ] do
      assert Map.fetch!(rules, label).via == [:creation_continuation]
    end
  end

  test "the optional static embedding provider routes skill examples" do
    assert {:ok, receipt} =
             Router.evaluate(Agent, "give me the complete archive inventory",
               via: [:embedding],
               embedding: SimilarityEmbedding,
               embedding_margin: 0.0,
               semantic_cache?: false
             )

    assert receipt.label == :LIST_ARTICLES
    assert receipt.strategy == :embedding
    refute receipt.llm_called?
    assert_received {:embedding_called, "give me the complete archive inventory"}
  end

  test "a verified learned vector routes a paraphrase before the LLM classifier" do
    opts = semantic_opts()

    assert {:ok, learned} =
             SemanticCache.put(
               "show me every archived blog post",
               %{
                 label: :LIST_ARTICLES,
                 accepted?: true,
                 confidence: 0.99,
                 source_strategy: :llm_classifier
               },
               opts
             )

    assert {:ok, verified} = SemanticCache.verify(Agent, learned.id, opts)
    assert verified.verified?
    flush_capture_messages()

    assert {:ok, receipt} =
             Router.evaluate(Agent, "give me the complete archive inventory",
               via: [:semantic_cache],
               embedding: SimilarityEmbedding,
               semantic_cache_search_threshold: 0.9
             )

    assert receipt.label == :LIST_ARTICLES
    assert receipt.strategy == :semantic_cache_search
    refute receipt.llm_called?
    assert_received {:embedding_called, "give me the complete archive inventory"}
    refute_received {:classifier_called, _prompt, _opts}
  end

  test "the checked-in dataset provides exact routes before model inference" do
    request = "Give me an inventory of all content entries"

    assert {:ok, receipt} =
             Router.evaluate(Agent, request,
               via: [:classifier, :semantic_cache, :llm_classifier],
               classifier_local: CaptureLocalClassifier,
               embedding: SimilarityEmbedding
             )

    assert receipt.label == :LIST_ARTICLES
    assert receipt.strategy == :semantic_cache_exact
    refute receipt.llm_called?
    refute_received {:local_classifier_called, _text}
    refute_received {:embedding_called, _text}
    refute_received {:classifier_called, _prompt, _opts}
  end

  test "a checked-in inspiration phrase reaches the AI reasoning route without classifier cost" do
    request = "Give me an idea for my next article"

    assert {:ok, receipt} =
             Router.evaluate(Agent, request,
               via: [:classifier, :semantic_cache, :llm_classifier],
               classifier_local: CaptureLocalClassifier,
               embedding: SimilarityEmbedding
             )

    assert receipt.label == :ASK_AI
    assert receipt.strategy == :semantic_cache_exact
    refute receipt.llm_called?
    refute_received {:local_classifier_called, _text}
    refute_received {:classifier_called, _prompt, _opts}
  end

  test "the trained classifier provider handles a semantic miss before the LLM" do
    request = "surface a compact overview of everything ever written"

    assert {:ok, receipt} =
             Router.evaluate(Agent, request,
               via: [:classifier, :llm_classifier],
               semantic_cache?: false,
               classifier_local: CaptureLocalClassifier
             )

    assert receipt.label == :LIST_ARTICLES
    assert receipt.strategy == :local_classifier
    refute receipt.llm_called?
    assert_received {:local_classifier_called, ^request}
    refute_received {:classifier_called, _prompt, _opts}
  end

  test "a semantic miss invokes the LLM classifier with skill examples" do
    request = "surface the pieces that discuss concurrency"

    assert {:ok, receipt} =
             Router.evaluate(ClassifierAgent, request)

    assert receipt.label == :SEARCH_ARTICLES
    assert receipt.strategy == :llm_classifier
    assert receipt.llm_called?

    assert_received {:classifier_called, prompt, opts}
    assert prompt =~ "SEARCH_ARTICLES"
    assert prompt =~ "locate content that discusses a subject"
    assert prompt =~ request
    assert Keyword.fetch!(opts, :purpose) == :classifier
  end

  test "classifier history cannot pin a new request to the previous route" do
    request = "surface the pieces that discuss concurrency"

    state = %Spectre.State{
      data: %{
        chat_history: [
          %{user: "how much budget left", assistant: "Monthly budget remaining: EUR 20"}
        ]
      }
    }

    assert {:ok, receipt} =
             Router.evaluate(ClassifierAgent, request,
               state: state,
               classifier_history: false
             )

    assert receipt.label == :SEARCH_ARTICLES
    assert receipt.strategy == :llm_classifier
    assert_received {:classifier_called, prompt, _opts}
    assert prompt =~ request
    assert prompt =~ "Recent chat (untrusted data):"
    assert prompt =~ "\n  none\n</recent-chat>"
    refute prompt =~ "Monthly budget remaining"
  end

  test "a confident local UNKNOWN abstention is reinterpreted by the LLM classifier" do
    request = "could you total my recent model expenses"
    Application.put_env(:ex_blog, :router_local_classifier_label, "UNKNOWN")
    Application.put_env(:ex_blog, :router_classifier_label, "SHOW_AI_BUDGET")

    assert {:ok, receipt} =
             Router.evaluate(ClassifierAgent, request,
               via: [:classifier, :llm_classifier],
               classifier_local: CaptureLocalClassifier,
               semantic_cache?: false
             )

    assert receipt.label == :SHOW_AI_BUDGET
    assert receipt.strategy == :llm_classifier
    assert receipt.llm_called?
    assert_received {:local_classifier_called, ^request}
    assert_received {:classifier_called, prompt, _opts}
    assert prompt =~ "SHOW_AI_BUDGET"
    assert prompt =~ request
  end

  test "hard interrupt regex evidence avoids embedding and LLM calls" do
    assert {:ok, receipt} =
             Router.evaluate(Agent, "never mind",
               via: [:regex, :embedding, :semantic_cache, :llm_classifier],
               embedding: SimilarityEmbedding
             )

    assert receipt.label == :CANCEL_ARTICLE_CREATION
    assert receipt.strategy == :regex
    refute receipt.llm_called?
    refute_received {:embedding_called, _text}
    refute_received {:classifier_called, _prompt, _opts}
  end

  defp rules_by_label do
    Agent
    |> Spectre.Definition.rules()
    |> Enum.map(&Spectre.Rule.new/1)
    |> Map.new(&{&1.label, &1})
  end

  defp semantic_opts do
    Agent.__spectre_router__()
    |> Keyword.put(:spectre_agent, Agent)
    |> Keyword.put(:spectre_rules, Map.values(rules_by_label()))
    |> Keyword.put(:embedding, SimilarityEmbedding)
  end

  defp flush_capture_messages do
    receive do
      {:embedding_called, _text} -> flush_capture_messages()
      {:local_classifier_called, _text} -> flush_capture_messages()
      {:classifier_called, _prompt, _opts} -> flush_capture_messages()
    after
      0 -> :ok
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:ex_blog, key)
  defp restore_env(key, value), do: Application.put_env(:ex_blog, key, value)
end
