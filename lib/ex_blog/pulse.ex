defmodule ExBlog.Pulse do
  @moduledoc """
  Spectre Pulse connection boundary between this blog and Spectre Studio.

  Pulse owns the authenticated WebSocket, the connection manifest, and the
  scoped OTP/Work/Vigil monitoring stream. It does not own the editorial Agent,
  its memory, its ledger, or any application authorization policy: this module
  only declares *which* connection exists, *which* Agent it exposes, and *which*
  scopes it may grant. `ExBlog.Pulse.Access` decides whether a caller gets them.

  The connection is configuration-gated and fails closed. Without
  `EX_BLOG_PULSE_TOKEN` no connection definition is registered, so
  `ExBlogWeb.PulseSocket` cannot resolve its `:studio` specification and rejects
  every upgrade before authentication runs.

  ## Scopes

  Runtime and operations monitoring are implemented by Pulse itself. ExBlog also
  implements durable semantic-cache review and a governed Morph proposal surface,
  so those three Studio bridge scopes are offered as well. Ledger, direct runtime
  Skill mounting, and Lab reads remain absent until the application implements a
  complete authorization boundary for them.
  """

  alias ExBlog.Config
  alias ExBlog.Pulse.Access

  # Mirrored by `ExBlogWeb.PulseSocket`, which needs a literal at compile time.
  @connection_id :studio

  @supported_scopes [
    "agent.runtime.read",
    "agent.runtime.stream",
    "agent.operations.read",
    "agent.operations.stream",
    "agent.semantic_cache.read",
    "agent.semantic_cache.promote",
    "spectre.morph.propose"
  ]

  @profiles ["pulse.messaging/1", "spectre.studio/1"]

  @doc "Identifier of the single connection definition served over `/pulse`."
  @spec connection_id() :: atom()
  def connection_id, do: @connection_id

  @doc "Scopes this deployment is able to serve, in manifest order."
  @spec supported_scopes() :: [String.t()]
  def supported_scopes, do: @supported_scopes

  @doc "Pulse protocol profiles advertised to a connected peer."
  @spec profiles() :: [String.t()]
  def profiles, do: @profiles

  @doc "The Agent exposed to Studio by this connection."
  @spec exposed_agents() :: [module()]
  def exposed_agents, do: [ExBlog.Agent]

  @doc """
  Whether a Studio connection is configured for this node.

  Requires both a validated token and the supervision flag tests use to keep
  Pulse out of the tree.
  """
  @spec enabled?(Config.t()) :: boolean()
  def enabled?(config \\ Config.get())

  def enabled?(%Config{} = config) do
    is_binary(Config.pulse_token(config)) and
      Application.get_env(:ex_blog, :start_pulse?, true)
  end

  @doc "Scopes this connection definition may grant, never more than it can serve."
  @spec scopes(Config.t()) :: [String.t()]
  def scopes(config \\ Config.get())

  def scopes(%Config{pulse_scopes: scopes}) when is_list(scopes),
    do: Enum.filter(@supported_scopes, &(&1 in scopes))

  @doc """
  Supervision children for the host Pulse runtime.

  Empty when no connection is configured, so a deployment without a token runs
  exactly as it did before Pulse existed.
  """
  @spec children(Config.t()) :: [Supervisor.child_spec() | {module(), keyword()}]
  def children(config \\ Config.get())

  def children(%Config{} = config) do
    if enabled?(config) do
      [{Spectre.Pulse, connections: [connection_spec(config)]}]
    else
      []
    end
  end

  @doc """
  The `:studio` connection definition.

  `mode: :listen` because this application never dials Studio; Studio dials it.
  The Agent allow-list is explicit rather than `:all` so a future Pulse-enabled
  Agent is not exposed to an existing operator token by accident.
  """
  @spec connection_spec(Config.t()) :: keyword()
  def connection_spec(config \\ Config.get())

  def connection_spec(%Config{} = config) do
    [
      id: @connection_id,
      transport: :websocket,
      mode: :listen,
      agents: exposed_agents(),
      authenticate: &Access.authenticate/2,
      authorize: &Access.authorize/2,
      scopes: scopes(config),
      profiles: @profiles,
      metadata: %{"application" => "ex_blog"}
    ]
  end

  @doc """
  The WebSocket URL an operator pastes into Studio's connection form.

  Phoenix appends the `/websocket` suffix to the `/pulse` mount, and the URL
  follows the canonical HTTPS origin the rest of the application publishes, so a
  development machine serving plain HTTP uses `ws://localhost:4000/pulse/websocket`
  instead. The token is never part of this value: Studio stores it separately,
  sealed by its own vault key.
  """
  @spec studio_url(Config.t()) :: String.t()
  def studio_url(config \\ Config.get())

  def studio_url(%Config{} = config) do
    config
    |> Config.canonical_url()
    |> String.replace_prefix("https://", "wss://")
    |> Kernel.<>("/pulse/websocket")
  end
end
