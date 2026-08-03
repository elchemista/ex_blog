defmodule ExBlog.Telegram.GatewayTest do
  use ExBlog.DataCase, async: false

  import ExUnit.CaptureLog

  alias ExBlog.Content.Asset
  alias ExBlog.Telegram.Gateway

  test "drops a non-admin update before invoking the processor or logging content" do
    event = telegram_update(999_999, "github-token-that-must-not-be-logged")

    log =
      capture_log(fn ->
        assert :ignore =
                 Gateway.handle_update(event,
                   processor: fn _event ->
                     send(self(), :processor_called)
                     {:reply, ["bad"]}
                   end
                 )
      end)

    refute_received :processor_called
    refute log =~ "github-token-that-must-not-be-logged"
  end

  test "lets the configured numeric administrator reach the processor" do
    admin_id = ExBlog.Config.get().admin_telegram_id
    event = telegram_update(admin_id, "/config")

    assert {:reply, ["ok"]} =
             Gateway.handle_update(event,
               processor: fn received ->
                 send(self(), {:authorized, received})
                 {:reply, ["ok"]}
               end
             )

    assert_received {:authorized, ^event}
  end

  test "splits plain-text replies within Telegram's limit" do
    chunks = Gateway.split(String.duplicate("a", 8_500))
    assert length(chunks) == 3
    assert Enum.all?(chunks, &(String.length(&1) <= 4_096))
    assert Enum.join(chunks) == String.duplicate("a", 8_500)
  end

  test "drops messages sent by the connected Telegram account" do
    admin_id = ExBlog.Config.get().admin_telegram_id
    {:ex_gram_message, jid, message} = telegram_update(admin_id, "/config")
    event = {:ex_gram_message, jid, %{message | from_me: true}}

    assert :ignore =
             Gateway.handle_update(event,
               processor: fn _event -> flunk("outgoing messages must not be processed") end
             )
  end

  test "routes an authenticated photo through Beam without downloading outside creation mode" do
    event = telegram_photo(ExBlog.Config.get().admin_telegram_id, 512)

    assert {:reply, [reply]} =
             Gateway.handle_update(event,
               telegram_media_downloader: fn _session, _ref, _opts ->
                 flunk("an image outside creation mode must not be downloaded")
               end
             )

    assert reply =~ "non c'è un draft in creazione"
  end

  test "rejects an oversized authenticated photo before Spectre or ExGram" do
    event =
      telegram_photo(
        ExBlog.Config.get().admin_telegram_id,
        Asset.max_bytes() + 1
      )

    assert {:reply, ["Immagine troppo grande: il limite è 10 MB."]} =
             Gateway.handle_update(event)
  end

  defp telegram_update(sender_id, text) do
    jid = Integer.to_string(sender_id)

    {:ex_gram_message, jid,
     %{
       id: 20,
       jid: jid,
       chat_id: sender_id,
       sender_id: sender_id,
       from_me: false,
       timestamp: 1_785_782_400,
       kind: :text,
       text: text,
       content: %{kind: :text, text: text}
     }}
  end

  defp telegram_photo(sender_id, size) do
    jid = Integer.to_string(sender_id)

    {:ex_gram_message, jid,
     %{
       id: 21,
       jid: jid,
       chat_id: sender_id,
       sender_id: sender_id,
       from_me: false,
       timestamp: 1_785_782_400,
       kind: :photo,
       text: "Copertina editoriale",
       media: %{type: :image, telegram_type: :photo, file_id: 77, size: size},
       content: %{
         kind: :media,
         text: "Copertina editoriale",
         media: %{type: :image, telegram_type: :photo, file_id: 77, size: size}
       }
     }}
  end
end
