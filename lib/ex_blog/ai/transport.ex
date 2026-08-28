defmodule ExBlog.AI.Transport do
  @moduledoc """
  Req transport for Prism with budget authorization and usage accounting.

  Every OpenRouter request crosses this boundary in the same order: authorize
  estimated spend, execute with Req, bound and decode the response, then record
  provider-reported usage. A successful HTTP response is not returned when
  usage accounting fails; silently losing cost data would break the budget
  guarantee for later requests.

  Retries are disabled here because Prism owns model-level attempts. Allowing
  Req to retry as well would make one logical attempt consume an unpredictable
  number of provider calls.
  """

  @behaviour Spectre.Prism.Adapter.Transport

  require Logger

  alias ExBlog.Budget
  alias ExBlog.Config

  @default_max_response_bytes 16_000_000

  @impl true
  def request(method, url, headers, body, opts)
      when method in [:get, :post, :put, :patch, :delete] and is_binary(url) and
             is_list(headers) and is_list(opts) do
    level = Keyword.get(opts, :ex_blog_level, level_for(body, opts))
    model = request_model(body)
    purpose = Keyword.get(opts, :purpose, :completion)
    started_at = System.monotonic_time()

    Logger.info(
      "openrouter_request started model=#{inspect(model)} purpose=#{inspect(purpose)} " <>
        "level=#{level}"
    )

    result = safe_perform_request(method, url, headers, body, opts, level)
    log_result(result, model, purpose, level, elapsed_ms(started_at))
    result
  end

  defp safe_perform_request(method, url, headers, body, opts, level) do
    perform_request(method, url, headers, body, opts, level)
  rescue
    exception -> {:error, {:transport_exception, Exception.message(exception)}}
  catch
    :exit, reason -> {:error, {:transport_exit, reason}}
    kind, reason -> {:error, {:transport_failure, kind, reason}}
  end

  defp perform_request(method, url, headers, body, opts, level) do
    with :ok <- Budget.authorize(level, budget_opts(opts)),
         {:ok, response} <- Req.request(request_options(method, url, headers, body, opts)),
         {:ok, decoded_body} <- decode_body(response.body, opts),
         :ok <- account(response.status, decoded_body, body, level, opts) do
      {:ok, response.status, normalize_headers(response.headers), decoded_body}
    end
  end

  defp request_options(method, url, headers, body, opts) do
    # Application and per-call Req options are useful for tests and deployment
    # tuning, but transport invariants below win during the final merge.
    :ex_blog
    |> Application.get_env(:openrouter_req_options, [])
    |> Keyword.merge(Keyword.get(opts, :req_options, []))
    |> Keyword.merge(
      method: method,
      url: url,
      headers: headers,
      receive_timeout:
        Keyword.get(
          opts,
          :receive_timeout,
          Application.get_env(:ex_blog, :openrouter_receive_timeout, 90_000)
        ),
      decode_body: false,
      retry: false,
      max_retries: 0
    )
    |> maybe_put_body(include_usage(body))
  end

  defp include_usage(%{"messages" => messages} = body) when is_list(messages) do
    Map.put_new(body, "usage", %{"include" => true})
  end

  defp include_usage(body), do: body

  defp maybe_put_body(options, nil), do: options
  defp maybe_put_body(options, body), do: Keyword.put(options, :json, body)

  defp decode_body(body, opts) when is_binary(body) do
    max_bytes = Keyword.get(opts, :max_response_bytes, @default_max_response_bytes)

    cond do
      not is_integer(max_bytes) or max_bytes <= 0 -> {:error, :invalid_max_response_bytes}
      byte_size(body) > max_bytes -> {:error, :response_too_large}
      body == "" -> {:ok, nil}
      true -> Jason.decode(body)
    end
  end

  defp decode_body(body, _opts) when is_map(body) or is_list(body) or is_nil(body),
    do: {:ok, body}

  defp decode_body(_body, _opts), do: {:error, :invalid_response_body}

  defp account(status, response, request, level, opts) when status in 200..299 do
    # OpenRouter may omit usage fields for some models. Missing numeric counters
    # become zero, while the request still records purpose and subject identity.
    usage = if is_map(response), do: Map.get(response, "usage", %{}), else: %{}

    attrs = %{
      purpose: Keyword.get(opts, :purpose, :completion),
      level: level,
      model: response_model(response, request),
      prompt_tokens: usage_value(usage, "prompt_tokens"),
      completion_tokens: usage_value(usage, "completion_tokens"),
      cost_usd: Map.get(usage, "cost", 0),
      subject_type: Keyword.get(opts, :subject_type),
      subject_ref: Keyword.get(opts, :subject_ref),
      conversation_id: Keyword.get(opts, :conversation_id)
    }

    case Budget.record(attrs) do
      {:ok, _usage} -> :ok
      {:error, reason} -> {:error, {:usage_accounting_failed, reason}}
    end
  end

  defp account(_status, _response, _request, _level, _opts), do: :ok

  defp response_model(response, request) do
    cond do
      is_map(response) and is_binary(Map.get(response, "model")) -> Map.get(response, "model")
      is_map(request) and is_binary(Map.get(request, "model")) -> Map.get(request, "model")
      true -> "unknown"
    end
  end

  defp request_model(%{"model" => model}) when is_binary(model), do: String.slice(model, 0, 160)
  defp request_model(_body), do: "unknown"

  defp log_result({:ok, status, _headers, _body}, model, purpose, level, duration_ms)
       when status in 200..299 do
    Logger.info(
      "openrouter_request completed model=#{inspect(model)} purpose=#{inspect(purpose)} " <>
        "level=#{level} status=#{status} duration_ms=#{duration_ms}"
    )
  end

  defp log_result({:ok, status, _headers, _body}, model, purpose, level, duration_ms) do
    Logger.warning(
      "openrouter_request failed model=#{inspect(model)} purpose=#{inspect(purpose)} " <>
        "level=#{level} code=provider_http_status status=#{status} duration_ms=#{duration_ms}"
    )
  end

  defp log_result({:error, reason}, model, purpose, level, duration_ms) do
    Logger.warning(
      "openrouter_request failed model=#{inspect(model)} purpose=#{inspect(purpose)} " <>
        "level=#{level} code=#{error_code(reason)} reason=#{inspect(safe_reason(reason))} " <>
        "duration_ms=#{duration_ms}"
    )
  end

  defp safe_reason(reason) do
    reason
    |> inspect(limit: 20, printable_limit: 1_000)
    |> Config.redact()
  end

  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp error_code(reason) when is_tuple(reason) and tuple_size(reason) > 0,
    do: reason |> elem(0) |> error_code()

  defp error_code(%{reason: reason}), do: error_code(reason)
  defp error_code(%{__struct__: module}) when is_atom(module), do: inspect(module)
  defp error_code(_reason), do: "unknown"

  defp elapsed_ms(started_at) do
    started_at
    |> then(&(System.monotonic_time() - &1))
    |> System.convert_time_unit(:native, :millisecond)
  end

  defp usage_value(usage, key) do
    case Map.get(usage, key, 0) do
      value when is_integer(value) and value >= 0 -> value
      _other -> 0
    end
  end

  defp budget_opts(opts) do
    Keyword.take(opts, [
      :estimated_cost_eur,
      :subject_type,
      :subject_ref
    ])
  end

  defp level_for(body, opts) do
    config = Config.get()
    model = if is_map(body), do: Map.get(body, "model"), else: nil

    cond do
      Keyword.get(opts, :purpose) in [:classifier, :route_classification] -> :fast
      model == config.fast_model -> :fast
      model == config.deep_model -> :deep
      true -> :balanced
    end
  end

  defp normalize_headers(headers) when is_map(headers) do
    Enum.flat_map(headers, fn {name, values} ->
      Enum.map(List.wrap(values), &{to_string(name), to_string(&1)})
    end)
  end
end
