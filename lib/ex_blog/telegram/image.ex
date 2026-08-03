defmodule ExBlog.Telegram.Image do
  @moduledoc """
  Converts an authenticated ExGram photo into a trusted Spectre flow input.

  `Spectre.Beam` normalizes the provider event first. This module then keeps
  only the numeric TDLib file id, declared size, and a redacted caption; remote
  identifiers and local TDLib paths never enter Spectre state. The actual bytes
  are downloaded only when the editorial skill confirms that an article flow
  is active.

  The generated `/attach-image` text is an internal deterministic intent. It
  lets the skill's global interrupt outrank whichever nested text field is
  currently waiting, while `current_flow` remains unchanged after attachment.
  """

  alias ExBlog.Config
  alias ExBlog.Content.Asset
  alias Spectre.Beam.Content
  alias Spectre.Beam.Inbound
  alias Spectre.Input
  alias Spectre.Input.Source

  @intent "/attach-image"
  @metadata_key :telegram_article_image

  @type downloaded :: %{
          bytes: binary(),
          caption: String.t() | nil,
          declared_size: non_neg_integer() | nil
        }

  @doc "Builds a normal text input or an internal image-attachment intent."
  @spec prepare(Inbound.t()) :: {:ok, Input.t()} | {:error, term()}
  def prepare(%Inbound{content: %Content{type: :image} = content} = inbound) do
    with true <- inbound.authenticated?,
         {:ok, file_id} <- positive_file_id(content.data),
         {:ok, declared_size} <- declared_size(content.data),
         :ok <- validate_declared_size(declared_size) do
      payload = %{
        file_id: file_id,
        declared_size: declared_size,
        caption: normalize_caption(content.text)
      }

      input =
        inbound
        |> Spectre.Beam.to_input()
        |> Map.put(:text, @intent)
        |> Input.put_meta(@metadata_key, payload)

      {:ok, input}
    else
      false -> {:error, :unauthenticated_telegram_image}
      {:error, _reason} = error -> error
    end
  end

  def prepare(%Inbound{} = inbound), do: {:ok, Spectre.Beam.to_input(inbound)}

  @doc "Downloads bytes for a previously prepared and authenticated input."
  @spec download(Input.t(), keyword()) :: {:ok, downloaded()} | {:error, term()}
  def download(%Input{} = input, opts \\ []) when is_list(opts) do
    with :ok <- trusted_telegram_source(input.source),
         {:ok, payload} <- Input.fetch_meta(input, @metadata_key),
         {:ok, result} <- download_media(payload, opts),
         {:ok, bytes} <- downloaded_bytes(result),
         :ok <- validate_downloaded_size(bytes) do
      {:ok,
       %{
         bytes: bytes,
         caption: Map.get(payload, :caption),
         declared_size: Map.get(payload, :declared_size)
       }}
    end
  end

  defp positive_file_id(data) do
    case field(data, :file_id) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _missing -> {:error, :missing_telegram_file_id}
    end
  end

  defp declared_size(data) do
    case field(data, :size) do
      nil -> {:ok, nil}
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _invalid -> {:error, :invalid_telegram_image_size}
    end
  end

  defp validate_declared_size(nil), do: :ok

  defp validate_declared_size(size) do
    if size <= Asset.max_bytes(), do: :ok, else: {:error, :telegram_image_too_large}
  end

  defp trusted_telegram_source(%Source{
         kind: :beam,
         mount: :telegram,
         metadata: %{authenticated?: true}
       }),
       do: :ok

  defp trusted_telegram_source(_source), do: {:error, :untrusted_telegram_image}

  defp download_media(%{file_id: file_id}, opts) do
    session_id = Keyword.get(opts, :telegram_session_id, Config.get().telegram_session_id)
    download_opts = [read_bytes: true, timeout_ms: 60_000, priority: 32]

    case Keyword.get(opts, :telegram_media_downloader) do
      fun when is_function(fun, 3) -> fun.(session_id, {:file_id, file_id}, download_opts)
      _default -> ExGram.download_media(session_id, {:file_id, file_id}, download_opts)
    end
  end

  defp downloaded_bytes(%{bytes: bytes}) when is_binary(bytes), do: {:ok, bytes}
  defp downloaded_bytes(%{"bytes" => bytes}) when is_binary(bytes), do: {:ok, bytes}
  defp downloaded_bytes(_result), do: {:error, :missing_downloaded_image_bytes}

  defp validate_downloaded_size(bytes) do
    size = byte_size(bytes)

    cond do
      size == 0 -> {:error, :empty_image}
      size > Asset.max_bytes() -> {:error, :telegram_image_too_large}
      true -> :ok
    end
  end

  defp normalize_caption(nil), do: nil

  defp normalize_caption(caption) when is_binary(caption) do
    caption
    |> Config.redact()
    |> String.trim()
    |> String.slice(0, 500)
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_caption(_caption), do: nil

  defp field(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp field(_value, _key), do: nil
end
