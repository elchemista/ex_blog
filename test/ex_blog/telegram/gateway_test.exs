defmodule ExBlog.Telegram.GatewayTest do
  use ExBlog.DataCase, async: false

  import ExUnit.CaptureLog

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
end
