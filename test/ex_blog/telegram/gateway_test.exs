defmodule ExBlog.Telegram.GatewayTest do
  use ExBlog.DataCase, async: false

  import ExUnit.CaptureLog

  alias ExBlog.Content.Asset
  alias ExBlog.Telegram.Gateway

  test "drops a non-admin update before invoking the processor or logging content" do
    event = telegram_update(999_999, "another_user", "github-token-that-must-not-be-logged")

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

  test "lets the configured administrator username reach the processor" do
    admin_username = ExBlog.Config.get().admin_telegram_username
    event = telegram_update(42, "@#{String.upcase(admin_username)}", "show the configuration")

    assert {:reply, ["ok"]} =
             Gateway.handle_update(event,
               processor: fn received ->
                 send(self(), {:authorized, received})
                 {:reply, ["ok"]}
               end
             )

    assert_received {:authorized, ^event}
  end

  test "resolves the username from the ExGram contact projection" do
    admin_username = ExBlog.Config.get().admin_telegram_username
    event = telegram_update(73_921, nil, "show the configuration")
    test_pid = self()

    assert {:reply, ["ok"]} =
             Gateway.handle_update(event,
               username_resolver: fn sender_id ->
                 send(test_pid, {:resolved_sender, sender_id})
                 {:ok, %{username: "@#{String.upcase(admin_username)}"}}
               end,
               processor: fn _event -> {:reply, ["ok"]} end
             )

    assert_received {:resolved_sender, 73_921}
  end

  test "resolves the username from modern TDLib usernames" do
    admin_username = ExBlog.Config.get().admin_telegram_username
    event = telegram_update(73_921, nil, "show the configuration")

    assert {:reply, ["ok"]} =
             Gateway.handle_update(event,
               username_resolver: fn _sender_id ->
                 {:ok,
                  %{
                    "usernames" => %{
                      "active_usernames" => [String.upcase(admin_username)],
                      "editable_username" => String.upcase(admin_username)
                    }
                  }}
               end,
               processor: fn _event -> {:reply, ["ok"]} end
             )
  end

  test "fails closed when Telegram cannot resolve the sender username" do
    event = telegram_update(73_921, nil, "show the configuration")

    assert :ignore =
             Gateway.handle_update(event,
               username_resolver: fn _sender_id -> {:error, :not_found} end,
               processor: fn _event -> flunk("an unresolved sender must not be processed") end
             )
  end

  test "splits plain-text replies within Telegram's limit" do
    chunks = Gateway.split(String.duplicate("a", 8_500))
    assert length(chunks) == 3
    assert Enum.all?(chunks, &(String.length(&1) <= 4_096))
    assert Enum.join(chunks) == String.duplicate("a", 8_500)
  end

  test "accepts administrator messages sent by the connected Telegram account" do
    admin_username = ExBlog.Config.get().admin_telegram_username

    {:ex_gram_message, jid, message} =
      telegram_update(42, admin_username, "show the configuration")

    event = {:ex_gram_message, jid, %{message | from_me: true}}

    assert {:reply, ["ok"]} =
             Gateway.handle_update(event,
               processor: fn received ->
                 send(self(), {:authorized, received})
                 {:reply, ["ok"]}
               end
             )

    assert_received {:authorized, ^event}
  end

  test "routes an authenticated photo through Beam without downloading outside creation mode" do
    event = telegram_photo(42, ExBlog.Config.get().admin_telegram_username, 512)

    assert {:reply, [reply]} =
             Gateway.handle_update(event,
               telegram_media_downloader: fn _session, _ref, _opts ->
                 flunk("an image outside creation mode must not be downloaded")
               end
             )

    assert reply =~ "no draft is being created"
  end

  test "rejects an oversized authenticated photo before Spectre or ExGram" do
    event =
      telegram_photo(
        42,
        ExBlog.Config.get().admin_telegram_username,
        Asset.max_bytes() + 1
      )

    assert {:reply, ["The image is too large. The limit is 10 MB."]} =
             Gateway.handle_update(event)
  end

  defp telegram_update(sender_id, sender_username, text) do
    jid = Integer.to_string(sender_id)

    {:ex_gram_message, jid,
     %{
       id: 20,
       jid: jid,
       chat_id: sender_id,
       sender_id: sender_id,
       sender_username: sender_username,
       from_me: false,
       timestamp: 1_785_782_400,
       kind: :text,
       text: text,
       content: %{kind: :text, text: text}
     }}
  end

  defp telegram_photo(sender_id, sender_username, size) do
    jid = Integer.to_string(sender_id)

    {:ex_gram_message, jid,
     %{
       id: 21,
       jid: jid,
       chat_id: sender_id,
       sender_id: sender_id,
       sender_username: sender_username,
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
