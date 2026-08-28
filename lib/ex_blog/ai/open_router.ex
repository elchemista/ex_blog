defmodule ExBlog.AI.OpenRouter do
  @moduledoc """
  Runtime OpenRouter adapter for ExBlog.

  Spectre's model catalog contains stable semantic placeholders only. This
  adapter resolves those placeholders to the deployed model names at call time
  and sends requests through `ExBlog.AI.Transport`, which owns budget
  authorization, Req transport, response bounds, and usage accounting.

  Keeping the HTTP boundary here also isolates ExBlog from provider-client
  option drift: application-only options such as `:transport`, `:purpose`, and
  `:ex_blog_level` never leak into ReqLLM's provider option validation.
  """

  @behaviour Spectre.Prism.Adapter
  @behaviour Spectre.LLM
  @behaviour Spectre.Classifier.Embedding

  alias ExBlog.Config
  alias Spectre.Inference.Response
  alias Spectre.Prism.Adapter.Client
  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.Adapter.Prompt
  alias Spectre.Prism.Adapters.OpenRouter, as: PrismOpenRouter
  alias Spectre.Prompt.Plan

  @provider :openrouter
  @base_url "https://openrouter.ai/api/v1"
  @markers %{
    fast: "ex-blog/runtime-fast",
    balanced: "ex-blog/runtime-balanced",
    deep: "ex-blog/runtime-deep"
  }
  @embedding_marker "ex-blog/runtime-embedding"
  @default_provider_routing %{"sort" => "throughput"}

  @impl Spectre.Prism.Adapter
  def catalog do
    PrismOpenRouter.catalog()
    |> Map.update!(:options, fn options ->
      options
      |> Keyword.put(:transport, ExBlog.AI.Transport)
      |> Keyword.put(:app_name, "ExBlog")
    end)
    |> Map.put(:embedding, model: @embedding_marker, dimensions: 1024)
  end

  @impl Spectre.LLM
  def complete(prompt, opts \\ [])

  def complete(prompt, opts) when is_binary(prompt) and is_list(opts) do
    opts = runtime_opts(opts)

    with :ok <- Client.validate_options(@provider, opts) do
      prompt
      |> Config.redact()
      |> Prompt.parts()
      |> complete_parts(opts)
    end
  end

  def complete(_prompt, _opts),
    do: {:error, Error.configuration(@provider, :invalid_prompt)}

  @impl Spectre.LLM
  def complete_plan(plan, opts)

  def complete_plan(%Plan{} = plan, opts) when is_list(opts) do
    opts = runtime_opts(opts)

    with :ok <- Client.validate_options(@provider, opts),
         :ok <- Client.validate_prompt_plan(@provider, plan) do
      plan
      |> redact_plan()
      |> Prompt.parts()
      |> complete_parts(opts)
    end
  end

  def complete_plan(_plan, _opts),
    do: {:error, Error.configuration(@provider, :invalid_prompt_plan)}

  @impl Spectre.Classifier.Embedding
  def load(_model, opts \\ []) when is_list(opts) do
    case Keyword.get(opts, :dimensions, Config.get().embedding_dimensions) do
      dimensions when is_integer(dimensions) and dimensions > 0 -> {:ok, dimensions}
      _invalid -> {:error, Error.configuration(@provider, :invalid_embedding_dimensions)}
    end
  end

  @impl Spectre.Classifier.Embedding
  def download(model, opts \\ []), do: load(model, opts)

  @impl Spectre.Classifier.Embedding
  def embed(input, opts \\ [])

  def embed(text, opts) when is_binary(text) and text != "" and is_list(opts) do
    with {:ok, [vector]} <- request_embeddings(Config.redact(text), 1, opts) do
      {:ok, vector}
    end
  end

  def embed(texts, opts) when is_list(texts) and is_list(opts) do
    if texts != [] and Enum.all?(texts, &(is_binary(&1) and &1 != "")) do
      safe_texts = Enum.map(texts, &Config.redact/1)
      request_embeddings(safe_texts, length(safe_texts), opts)
    else
      {:error, Error.configuration(@provider, :invalid_embedding_input)}
    end
  end

  def embed(_input, _opts),
    do: {:error, Error.configuration(@provider, :invalid_embedding_input)}

  @spec marker(:fast | :balanced | :deep) :: String.t()
  def marker(level), do: Map.fetch!(@markers, level)

  @spec complete_parts(Prompt.parts(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  defp complete_parts(parts, opts) do
    with {:ok, key} <- Client.api_key(@provider, opts, "OPENROUTER_API_KEY"),
         {:ok, body, _headers} <-
           Client.post(
             @provider,
             Client.url(Keyword.get(opts, :base_url, @base_url), "/chat/completions"),
             request_headers(key, opts),
             chat_body(parts, opts),
             opts
           ) do
      normalize_response(body)
    end
  end

  @spec request_embeddings(String.t() | [String.t()], pos_integer(), keyword()) ::
          {:ok, [[float()]]} | {:error, Error.t()}
  defp request_embeddings(input, expected_count, opts) do
    with {:ok, key} <- Client.api_key(@provider, opts, "OPENROUTER_API_KEY"),
         {:ok, body, _headers} <-
           Client.post(
             @provider,
             Client.url(Keyword.get(opts, :base_url, @base_url), "/embeddings"),
             request_headers(key, opts),
             embedding_body(input, opts),
             opts
           ) do
      Client.embedding_vectors(@provider, body, expected_count)
    end
  end

  @spec chat_body(Prompt.parts(), keyword()) :: map()
  defp chat_body(parts, opts) do
    %{
      "model" => Keyword.fetch!(opts, :model),
      "messages" => Prompt.messages(parts),
      "stream" => false
    }
    |> Client.put_option("max_tokens", opts, [
      :max_tokens,
      :max_output_tokens,
      :maximum_output_tokens
    ])
    |> Client.put_option("reasoning", opts, [:reasoning])
    |> Client.put_option("reasoning_effort", opts, [:reasoning_effort])
    |> Client.put_option("include_reasoning", opts, [:include_reasoning])
    |> Client.put_option("temperature", opts, [:temperature])
    |> Client.put_option("top_p", opts, [:top_p])
    |> Client.put_option("top_k", opts, [:top_k])
    |> Client.put_option("min_p", opts, [:min_p])
    |> Client.put_option("response_format", opts, [:response_format])
    |> Client.put_option("seed", opts, [:seed])
    |> Client.put_option("stop", opts, [:stop])
    |> Client.put_option("tools", opts, [:tools])
    |> Client.put_option("tool_choice", opts, [:tool_choice])
    |> Client.put_option("provider", opts, [:provider_routing])
  end

  @spec embedding_body(String.t() | [String.t()], keyword()) :: map()
  defp embedding_body(input, opts) do
    %{
      "model" => Keyword.fetch!(opts, :model),
      "input" => input,
      "encoding_format" => "float"
    }
    |> Client.put_option("encoding_format", opts, [:encoding_format])
    |> Client.put_option("dimensions", opts, [:dimensions])
  end

  @spec request_headers(String.t(), keyword()) :: [{String.t(), String.t()}]
  defp request_headers(key, opts) do
    defaults = [
      {"authorization", "Bearer " <> key},
      {"content-type", "application/json"}
    ]

    defaults
    |> maybe_header("HTTP-Referer", Keyword.get(opts, :site_url))
    |> maybe_header("X-OpenRouter-Title", Keyword.get(opts, :app_name))
    |> Client.headers(opts)
  end

  @spec normalize_response(term()) :: {:ok, Response.t()} | {:error, Error.t()}
  defp normalize_response(body) when is_map(body) do
    case Client.provider_error(body) do
      nil -> build_response(body)
      error -> {:error, Error.provider(@provider, Client.provider_error_code(error))}
    end
  end

  defp normalize_response(_body),
    do: {:error, Error.invalid_response(@provider, :response_not_an_object)}

  @spec build_response(map()) :: {:ok, Response.t()} | {:error, Error.t()}
  defp build_response(body) do
    choice = body |> Map.get("choices", []) |> List.first()
    text = message_text(choice)

    if is_binary(text) and text != "" do
      {:ok,
       Response.new(%{
         text: text,
         provider_request_id: Map.get(body, "id"),
         usage: usage(Map.get(body, "usage", %{})),
         metadata: %{
           provider: @provider,
           model: Map.get(body, "model"),
           finish_reason: choice_value(choice, "finish_reason")
         }
       })}
    else
      {:error, Error.invalid_response(@provider, :missing_output_text)}
    end
  end

  @spec message_text(term()) :: String.t() | nil
  defp message_text(%{"message" => %{"content" => content}}) when is_binary(content),
    do: content

  defp message_text(%{"message" => %{"content" => content}}) when is_list(content) do
    text =
      content
      |> Enum.flat_map(fn
        %{"type" => "text", "text" => text} when is_binary(text) -> [text]
        %{"text" => text} when is_binary(text) -> [text]
        _part -> []
      end)
      |> Enum.join("")

    if text == "", do: nil, else: text
  end

  defp message_text(_choice), do: nil

  @spec choice_value(term(), String.t()) :: term()
  defp choice_value(choice, key) when is_map(choice), do: Map.get(choice, key)
  defp choice_value(_choice, _key), do: nil

  @spec usage(term()) :: map()
  defp usage(usage) when is_map(usage) do
    %{
      input_tokens: Client.token_count(usage, "prompt_tokens"),
      output_tokens: Client.token_count(usage, "completion_tokens"),
      total_tokens: Client.token_count(usage, "total_tokens")
    }
  end

  defp usage(_usage), do: %{}

  defp runtime_opts(opts) do
    config = Config.get()
    selected = Keyword.get(opts, :model)
    level = selected_level(selected, opts)

    model =
      cond do
        classifier_purpose?(opts) -> config.classifier_model
        kinetic_planner_purpose?(opts) -> planner_model!(selected)
        true -> runtime_model(level, config)
      end

    opts
    |> Keyword.put(:transport, ExBlog.AI.Transport)
    |> Keyword.put(:api_key, Config.fetch_secret!(:openrouter_api_key))
    |> Keyword.put(:app_name, "ExBlog")
    |> Keyword.put(:model, model)
    |> Keyword.put(:ex_blog_level, level)
    |> Keyword.put_new(:provider_routing, @default_provider_routing)
    |> Keyword.put_new(:receive_timeout, 90_000)
  end

  defp selected_level(selected, opts) do
    if classifier_purpose?(opts), do: :fast, else: marker_level(selected)
  end

  defp marker_level(selected) do
    Enum.find_value(@markers, :balanced, fn
      {level, ^selected} -> level
      _marker -> nil
    end)
  end

  defp runtime_model(:fast, config), do: config.fast_model
  defp runtime_model(:balanced, config), do: config.balanced_model
  defp runtime_model(:deep, config), do: config.deep_model

  defp planner_model!(model) when is_binary(model) do
    model = model |> String.trim() |> String.replace_prefix("openrouter:", "")

    if model == "" do
      raise ArgumentError, "Kinetic planner calls require an explicit OpenRouter model"
    else
      model
    end
  end

  defp planner_model!(_model) do
    raise ArgumentError, "Kinetic planner calls require an explicit OpenRouter model"
  end

  defp classifier_purpose?(opts),
    do: Keyword.get(opts, :purpose) in [:classifier, :route_classification]

  defp kinetic_planner_purpose?(opts), do: Keyword.get(opts, :purpose) == :kinetic_planner

  defp redact_plan(plan) do
    plan =
      Enum.reduce([:protected, :instructions, :context, :examples, :task], plan, fn field, acc ->
        Map.update!(acc, field, &Enum.map(&1, fn fragment -> redact_fragment(fragment) end))
      end)

    %{plan | rendered: Config.redact(plan.rendered)}
  end

  defp redact_fragment(%{content: content} = fragment) when is_binary(content),
    do: %{fragment | content: Config.redact(content)}

  defp redact_fragment(fragment), do: fragment

  defp maybe_header(headers, _name, nil), do: headers
  defp maybe_header(headers, name, value) when is_binary(value), do: headers ++ [{name, value}]
  defp maybe_header(headers, _name, _value), do: headers
end
