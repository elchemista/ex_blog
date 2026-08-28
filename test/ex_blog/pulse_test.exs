defmodule ExBlog.PulseTest do
  # The runtime configuration lives in `:persistent_term`, so a test that
  # installs a connection token has to own it for the duration of the test.
  use ExUnit.Case, async: false

  alias ExBlog.Config
  alias ExBlog.Pulse
  alias ExBlog.Pulse.Access
  alias Spectre.Pulse.Principal

  @token String.duplicate("pulse-token-", 4)

  setup do
    previous = Config.get()
    on_exit(fn -> Config.install(previous) end)

    :ok
  end

  describe "connection definition" do
    # `use Spectre.Pulse.Phoenix` needs a literal, so `ExBlogWeb.PulseSocket`
    # cannot read this value. That the two copies agree is proven end to end by
    # `ExBlogWeb.PulseSocketTest`, which completes a handshake through the
    # generated transport.
    test "is named :studio" do
      assert Pulse.connection_id() == :studio
    end

    test "exposes only the editorial agent, over a listening websocket" do
      config = install(pulse_token: @token)
      spec = Pulse.connection_spec(config)

      assert spec[:id] == :studio
      assert spec[:transport] == :websocket
      assert spec[:mode] == :listen
      assert spec[:agents] == [ExBlog.Agent]
      assert spec[:authenticate] == (&Access.authenticate/2)
      assert spec[:authorize] == (&Access.authorize/2)
    end

    test "offers only the scopes Pulse itself enforces" do
      assert Pulse.supported_scopes() == [
               "agent.runtime.read",
               "agent.runtime.stream",
               "agent.operations.read",
               "agent.operations.stream"
             ]

      # Studio transports these, but the host implements them, and this host
      # does not. Granting one would render a panel that can only fail.
      for unimplemented <- [
            "agent.message.send",
            "agent.semantic_cache.read",
            "agent.semantic_cache.promote",
            "spectre.skill.runtime.mount",
            "spectre.morph.propose",
            "ledger.read",
            "lab.read"
          ] do
        refute unimplemented in Pulse.supported_scopes()
      end
    end

    test "narrows the granted scopes to the configured subset" do
      config = install(pulse_scopes: ["agent.runtime.read", "agent.operations.read"])

      assert Pulse.scopes(config) == ["agent.runtime.read", "agent.operations.read"]
      assert Pulse.connection_spec(config)[:scopes] == Pulse.scopes(config)
    end

    test "never grants a scope this deployment cannot serve" do
      config = install(pulse_scopes: ["agent.runtime.read", "ledger.read"])

      assert Pulse.scopes(config) == ["agent.runtime.read"]
    end
  end

  describe "supervision" do
    setup do
      # `config/test.exs` keeps Pulse out of the tree so no test opens a
      # listening Studio socket by accident; these assertions are about what a
      # deployment with the flag on does.
      previous = Application.get_env(:ex_blog, :start_pulse?)
      on_exit(fn -> Application.put_env(:ex_blog, :start_pulse?, previous) end)
      Application.put_env(:ex_blog, :start_pulse?, true)

      :ok
    end

    test "starts nothing without a configured token" do
      config = install(pulse_token: nil)

      refute Pulse.enabled?(config)
      assert Pulse.children(config) == []
    end

    test "starts the Pulse runtime once a token is configured" do
      config = install(pulse_token: @token)

      assert Pulse.enabled?(config)
      assert [{Spectre.Pulse, connections: [spec]}] = Pulse.children(config)
      assert spec[:id] == :studio
    end

    test "honours the supervision flag even with a token" do
      config = install(pulse_token: @token)
      Application.put_env(:ex_blog, :start_pulse?, false)

      refute Pulse.enabled?(config)
      assert Pulse.children(config) == []
    end
  end

  describe "authentication" do
    test "accepts the configured token and returns a Studio principal" do
      config = install(pulse_token: @token)

      assert {:ok, attrs} = Access.authenticate(transport_info(@token), context())
      assert {:ok, principal} = Principal.new(attrs)

      assert principal.kind == :studio
      assert principal.identity == "spectre://studio/operator"
      assert principal.scopes == Pulse.scopes(config)
      assert principal.verified["issuer"] == "ex_blog"
      assert principal.verified["peer_ip"] == "127.0.0.1"
    end

    test "the principal identifies the credential without revealing it" do
      install(pulse_token: @token)

      assert {:ok, attrs} = Access.authenticate(transport_info(@token), context())

      refute attrs.id =~ @token
      refute inspect(attrs) =~ @token
      assert attrs.id == Access.principal_id(@token)
    end

    test "rotating the token changes the principal id" do
      refute Access.principal_id(@token) == Access.principal_id(@token <> "-rotated")
    end

    test "rejects a wrong token" do
      install(pulse_token: @token)

      assert {:error, :invalid_pulse_token} =
               Access.authenticate(transport_info(String.duplicate("x", 48)), context())
    end

    test "rejects a token of a different length without comparing further" do
      install(pulse_token: @token)

      assert {:error, :invalid_pulse_token} =
               Access.authenticate(transport_info(@token <> "!"), context())
    end

    test "rejects a missing or blank token" do
      install(pulse_token: @token)

      assert {:error, :pulse_token_required} =
               Access.authenticate(%{params: %{}}, context())

      assert {:error, :pulse_token_required} = Access.authenticate(transport_info(""), context())
    end

    test "rejects every connection when no token is configured" do
      install(pulse_token: nil)

      assert {:error, :pulse_connection_not_configured} =
               Access.authenticate(transport_info(@token), context())
    end
  end

  describe "authorization" do
    test "grants the intersection of the definition and the principal" do
      install(pulse_token: @token)

      request = request(Pulse.supported_scopes())
      principal = principal(["agent.runtime.read", "agent.operations.read"])

      assert {:ok, grants} = Access.authorize(principal, request)

      assert grants[:granted_scopes] == ["agent.runtime.read", "agent.operations.read"]
      assert grants[:granted_profiles] == Pulse.profiles()
    end

    test "a principal scope absent from the definition is not granted" do
      request = request(["agent.runtime.read"])
      principal = principal(Pulse.supported_scopes())

      assert {:ok, grants} = Access.authorize(principal, request)
      assert grants[:granted_scopes] == ["agent.runtime.read"]
    end

    test "a scope this deployment cannot serve is dropped even if both sides claim it" do
      request = request(["agent.runtime.read", "ledger.read"])
      principal = principal(["agent.runtime.read", "ledger.read"])

      assert {:ok, grants} = Access.authorize(principal, request)
      assert grants[:granted_scopes] == ["agent.runtime.read"]
    end

    test "refuses a connection that would be granted nothing" do
      request = request(["agent.runtime.read"])
      principal = principal(["agent.operations.read"])

      assert {:error, :no_pulse_scope_granted} = Access.authorize(principal, request)
    end
  end

  describe "studio_url/1" do
    test "follows the canonical origin as a secure websocket" do
      config = install(phx_host: "blog.example.com")

      assert Pulse.studio_url(config) == "wss://blog.example.com/pulse/websocket"
    end
  end

  defp install(overrides) do
    config = struct!(Config.get(), overrides)
    :ok = Config.install(config)
    config
  end

  defp transport_info(token) do
    %{
      params: %{"token" => token},
      connect_info: %{peer_data: %{address: {127, 0, 0, 1}, port: 51_234, ssl_cert: nil}},
      endpoint: ExBlogWeb.Endpoint,
      transport: :websocket,
      options: []
    }
  end

  defp context do
    %{
      binding: :websocket,
      endpoint: ExBlogWeb.Endpoint,
      transport: :websocket,
      peer_data: %{address: {127, 0, 0, 1}, port: 51_234, ssl_cert: nil}
    }
  end

  defp request(scopes) do
    %{
      connection_spec: %{id: :studio, transport: :websocket, scopes: scopes},
      context: %{binding: :websocket},
      direction: :inbound,
      requested_profiles: [],
      requested_scopes: []
    }
  end

  defp principal(scopes) do
    {:ok, principal} =
      Principal.new(%{
        id: "studio-test",
        identity: "spectre://studio/operator",
        kind: :studio,
        scopes: scopes
      })

    principal
  end
end
