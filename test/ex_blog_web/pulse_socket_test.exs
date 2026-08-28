defmodule ExBlogWeb.PulseSocketTest do
  @moduledoc """
  Drives `ExBlogWeb.PulseSocket` through the callbacks Phoenix invokes on a real
  `/pulse/websocket` upgrade. Everything below the HTTP handshake is exercised:
  the connection definition, both access callbacks, the manifest, the monitoring
  control surface, and the inbound boundary.
  """

  # Installs a connection token into the global runtime configuration and starts
  # the singleton Pulse runtime.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ExBlog.Agent.Instance
  alias ExBlog.Config
  alias ExBlog.Pulse
  alias ExBlogWeb.PulseSocket

  @token String.duplicate("socket-token-", 4)
  @address "spectre://ex-blog/editorial"
  @subject "blog-operations"

  setup do
    previous = Config.get()
    on_exit(fn -> Config.install(previous) end)

    config = struct!(previous, pulse_token: @token, pulse_scopes: Pulse.supported_scopes())
    :ok = Config.install(config)

    start_supervised!({Spectre.Pulse, connections: [Pulse.connection_spec(config)]})

    :ok
  end

  describe "handshake" do
    test "refuses an upgrade without a token" do
      assert {:error, _reason} = PulseSocket.connect(transport_info(nil))
    end

    test "refuses an upgrade with the wrong token" do
      assert {:error, _reason} = PulseSocket.connect(transport_info(String.duplicate("x", 48)))
    end

    test "refuses every upgrade once the token is removed" do
      :ok = Config.install(struct!(Config.get(), pulse_token: nil))

      assert {:error, _reason} = PulseSocket.connect(transport_info(@token))
    end

    test "opens one connection and pushes a credential-free manifest" do
      {manifest, state} = connect!()

      assert manifest["type"] == "manifest"
      assert manifest["spec"]["id"] == "studio"
      assert manifest["spec"]["mode"] == "listen"

      connection = manifest["connection"]
      assert connection["principal"]["identity"] == "spectre://studio/operator"
      assert connection["principal"]["kind"] == "studio"
      assert connection["granted_scopes"] == Pulse.supported_scopes()
      assert connection["local_agent_addresses"] == [@address]
      assert connection["verified"]["issuer"] == "ex_blog"

      assert [agent] = manifest["agents"]
      assert agent["address"] == @address
      assert agent["display_name"] == "ExBlog editorial agent"
      assert "editorial" in agent["capabilities"]

      refute Jason.encode!(manifest) =~ @token

      close(state)
    end

    test "removes the live connection when the socket terminates" do
      {manifest, state} = connect!()
      connection_id = manifest["connection"]["id"]

      assert Enum.any?(Spectre.Pulse.connections(), &(&1.id == connection_id))

      close(state)

      refute Enum.any?(Spectre.Pulse.connections(), &(&1.id == connection_id))
    end
  end

  describe "runtime monitoring" do
    test "lists active Instances for current Spectre Studio clients" do
      {_manifest, state} = connect!()
      {:ok, _pid} = Instance.ensure()

      assert {:reply, :ok, {:text, frame}, state} =
               PulseSocket.handle_in({instances_list(), [opcode: :text]}, state)

      assert %{
               "type" => "agent.instances.list.result",
               "agent_address" => @address,
               "count" => 1,
               "instances" => [instance]
             } = Jason.decode!(frame)

      assert instance["subject"] == @subject
      assert instance["alive"] == true

      close(state)
    end

    test "streams a snapshot of the live Agent Instance" do
      {_manifest, state} = connect!()
      {:ok, _pid} = Instance.ensure()

      assert {:reply, :ok, {:text, frame}, state} =
               PulseSocket.handle_in({monitor_enable(), [opcode: :text]}, state)

      event = Jason.decode!(frame)

      assert event["type"] == "agent.runtime.monitor.enabled"
      assert event["agent_address"] == @address
      assert event["sequence"] == 0
      assert event["snapshot"]["alive"] == true
      assert is_integer(event["snapshot"]["process"]["memory"])

      # No mailbox contents, process dictionary, or GenServer state.
      assert Map.keys(event["snapshot"]["process"]) |> Enum.sort() ==
               ["memory", "message_queue_len", "status"]

      close(state)
    end

    test "reports a missing Instance instead of starting one" do
      {_manifest, state} = connect!()

      log =
        capture_log([level: :warning], fn ->
          assert {:reply, :error, {:text, frame}, _next_state} =
                   PulseSocket.handle_in(
                     {monitor_enable(subject: "never-summoned"), [opcode: :text]},
                     state
                   )

          assert %{"type" => "error", "error" => %{"code" => "instance_not_found"}} =
                   Jason.decode!(frame)
        end)

      assert log =~ "pulse_request failed"
      assert log =~ ~s(code="instance_not_found")
      assert log =~ "duration_ms="

      close(state)
    end

    test "refuses to monitor an Agent this connection does not expose" do
      {_manifest, state} = connect!()

      assert {:reply, :error, {:text, frame}, state} =
               PulseSocket.handle_in(
                 {monitor_enable(agent_address: "spectre://ex-blog/other"), [opcode: :text]},
                 state
               )

      assert %{"type" => "error"} = Jason.decode!(frame)

      close(state)
    end

    test "refuses a stream the connection was not granted" do
      :ok =
        Config.install(struct!(Config.get(), pulse_scopes: ["agent.runtime.read"]))

      stop_supervised!(Spectre.Pulse)
      start_supervised!({Spectre.Pulse, connections: [Pulse.connection_spec()]})

      {manifest, state} = connect!()
      assert manifest["connection"]["granted_scopes"] == ["agent.runtime.read"]

      {:ok, _pid} = Instance.ensure()

      assert {:reply, :error, {:text, frame}, state} =
               PulseSocket.handle_in({monitor_enable(), [opcode: :text]}, state)

      assert %{"type" => "error"} = Jason.decode!(frame)

      close(state)
    end
  end

  describe "inbound envelopes" do
    test "refuses every payload type, so a connection cannot drive the Agent" do
      {_manifest, state} = connect!()

      envelope =
        Jason.encode!(%{
          "version" => 1,
          "id" => Spectre.Identity.uuid7(),
          "from" => "spectre://studio/operator",
          "to" => @address,
          "act" => "request",
          "payload" => %{"type" => "research.perform", "data" => %{"topic" => "anything"}},
          "metadata" => %{}
        })

      assert {:reply, :error, {:text, frame}, state} =
               PulseSocket.handle_in({envelope, [opcode: :text]}, state)

      assert %{
               "type" => "error",
               "error" => %{
                 "kind" => "authorization",
                 "code" => "payload_type_not_allowed"
               }
             } = Jason.decode!(frame)

      close(state)
    end

    test "refuses an envelope whose sender is not the authenticated identity" do
      {_manifest, state} = connect!()

      envelope =
        Jason.encode!(%{
          "version" => 1,
          "id" => Spectre.Identity.uuid7(),
          "from" => "spectre://studio/somebody-else",
          "to" => @address,
          "act" => "request",
          "payload" => %{"type" => "research.perform", "data" => %{}},
          "metadata" => %{}
        })

      assert {:reply, :error, {:text, frame}, state} =
               PulseSocket.handle_in({envelope, [opcode: :text]}, state)

      assert %{"error" => %{"kind" => "authentication"}} = Jason.decode!(frame)

      close(state)
    end
  end

  defp connect!(token \\ @token) do
    assert {:ok, ticket} = PulseSocket.connect(transport_info(token))
    assert {:ok, state} = PulseSocket.init(ticket)

    assert_receive {:spectre_pulse_manifest, connection_id}

    assert {:push, {:text, frame}, state} =
             PulseSocket.handle_info({:spectre_pulse_manifest, connection_id}, state)

    {Jason.decode!(frame), state}
  end

  defp close(state), do: PulseSocket.terminate(:normal, state)

  defp transport_info(token) do
    %{
      params: if(token, do: %{"token" => token}, else: %{}),
      connect_info: %{peer_data: %{address: {127, 0, 0, 1}, port: 51_234, ssl_cert: nil}},
      endpoint: ExBlogWeb.Endpoint,
      transport: :websocket,
      options: []
    }
  end

  defp monitor_enable(overrides \\ []) do
    Jason.encode!(%{
      "pulse" => "connection",
      "version" => 1,
      "type" => "agent.runtime.monitor.enable",
      "request_id" => "test-panel",
      "agent_address" => Keyword.get(overrides, :agent_address, @address),
      "subject" => Keyword.get(overrides, :subject, @subject),
      "interval_ms" => 1_000,
      "duration_ms" => 5_000,
      "fields" => ["memory", "message_queue_len", "status"]
    })
  end

  defp instances_list do
    Jason.encode!(%{
      "pulse" => "connection",
      "version" => 1,
      "type" => "agent.instances.list",
      "request_id" => "test-instances-panel",
      "agent_address" => @address
    })
  end
end
