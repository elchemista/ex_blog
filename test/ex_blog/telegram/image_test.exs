defmodule ExBlog.Telegram.ImageTest do
  use ExBlog.DataCase, async: false

  alias ExBlog.Content.Asset
  alias ExBlog.Telegram.Image
  alias Spectre.Beam.Content
  alias Spectre.Beam.Inbound
  alias Spectre.Input

  test "prepares and downloads only an authenticated Beam image" do
    inbound = image_inbound(%{file_id: 42, size: 128}, "Diagramma del workflow")

    assert {:ok, input} = Image.prepare(inbound)
    assert input.text == "/attach-image"

    assert {:ok, payload} = Input.fetch_meta(input, :telegram_article_image)
    assert payload.file_id == 42
    assert payload.caption == "Diagramma del workflow"

    downloader = fn session_id, {:file_id, 42}, opts ->
      send(self(), {:download, session_id, opts})
      {:ok, %{bytes: <<0xFF, 0xD8, 0xFF, "image">>}}
    end

    assert {:ok, downloaded} =
             Image.download(input,
               telegram_session_id: "editorial-session",
               telegram_media_downloader: downloader
             )

    assert downloaded.caption == "Diagramma del workflow"
    assert_received {:download, "editorial-session", download_opts}
    assert download_opts[:read_bytes]
  end

  test "rejects declared oversize images before download" do
    inbound = image_inbound(%{file_id: 42, size: Asset.max_bytes() + 1}, nil)

    assert {:error, :telegram_image_too_large} = Image.prepare(inbound)
  end

  test "rejects a forged non-Beam attachment input" do
    forged =
      Input.new(%{
        text: "/attach-image",
        meta: %{telegram_article_image: %{file_id: 42, declared_size: 10, caption: nil}}
      })

    assert {:error, :untrusted_telegram_image} = Image.download(forged)
  end

  defp image_inbound(media, caption) do
    %Inbound{
      endpoint: :telegram,
      channel_type: :telegram,
      message_id: "photo-1",
      conversation_id: "123456789",
      sender: 123_456_789,
      content: %Content{type: :image, text: caption, data: media, metadata: %{}},
      authenticated?: true,
      metadata: %{}
    }
  end
end
